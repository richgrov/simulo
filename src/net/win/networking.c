#include "networking.h"

#include <stddef.h>

#include <MSWSock.h>
#include <WinSock2.h>

#include "config.h"
#include "protocol/packets.h"
#include "util/arrays.h"
#include "util/debug_assert.h"

static void close_or_log_error(SOCKET socket) {
   if (closesocket(socket) != SOCKET_ERROR) {
      return;
   }

   int err = WSAGetLastError();
   SIMULO_PANIC("Failed to close %llu: %d", socket, err);
}

static void load_accept_ex(SOCKET listener, LPFN_ACCEPTEX *fn) {
   GUID accept_ex_guid = WSAID_ACCEPTEX;
   DWORD unused;
   int load_result = WSAIoctl(
      listener, SIO_GET_EXTENSION_FUNCTION_POINTER, &accept_ex_guid, sizeof(accept_ex_guid), fn,
      sizeof(LPFN_ACCEPTEX), &unused, NULL, NULL
   );

   if (load_result == SOCKET_ERROR) {
      SIMULO_PANIC("fatal: couldn't load AcceptEx: WSAIoctl returned %d", WSAGetLastError());
   }
}

#define LISTENER_COMPLETION_KEY -1
#define OUT_OF_CONNECTIONS -1

static void init_conn_slab(Networking *net) {
   for (int i = 0; i < ARRAY_LEN(net->connections); ++i) {
      if (i == ARRAY_LEN(net->connections) - 1) {
         net->connections[i].next = OUT_OF_CONNECTIONS;
      } else {
         net->connections[i].next = i + 1;
      }
   }
   net->next_avail_connection = 0;
}

bool net_init(Networking *net, const uint16_t port, IncomingConnection *accepted_connections) {
   memset(net, 0, sizeof(Networking));

   init_conn_slab(net);
   net->accepted_socket = INVALID_SOCKET;
   net->accepted_connections = accepted_connections;

   struct WSAData wsa_data;
   int startup_res = WSAStartup(MAKEWORD(2, 2), &wsa_data);
   if (startup_res != 0) {
      fprintf(stderr, "error: WSAStartup returned %d", startup_res);
      return false;
   }

   net->root_completion_port = CreateIoCompletionPort(INVALID_HANDLE_VALUE, NULL, 0, 0);
   if (net->root_completion_port == NULL) {
      fprintf(stderr, "error: CreateIOCompletionPort returned %lu", GetLastError());
      return false;
   }

   net->listen_socket = socket(AF_INET, SOCK_STREAM, 0);
   if (net->listen_socket == INVALID_SOCKET) {
      fprintf(stderr, "error: socket returned %d", WSAGetLastError());
      return false;
   }

   load_accept_ex(net->listen_socket, &net->accept_ex);

   SOCKADDR_IN bind_addr;
   bind_addr.sin_family = AF_INET;
   bind_addr.sin_addr.s_addr = INADDR_ANY;
   bind_addr.sin_port = htons(port);
   if (bind(net->listen_socket, (struct sockaddr *)&bind_addr, sizeof(bind_addr)) == SOCKET_ERROR) {
      fprintf(stderr, "error: bind returned %d", WSAGetLastError());
      return false;
   }

   return true;
}

static void release_connection(Networking *net, int connection_key) {
   SIMULO_DEBUG_ASSERT(
      connection_key >= 0 && connection_key < ARRAY_LEN(net->connections),
      "tried to release connection %d", connection_key
   );

   Connection *conn = &net->connections[connection_key];
   if (conn->socket != INVALID_SOCKET) {
      close_or_log_error(conn->socket);
   }

   net->connections[connection_key].next = net->next_avail_connection;
   net->next_avail_connection = connection_key;
}

void net_deinit(Networking *net) {
   bool unallocated_connections[ARRAY_LEN(net->connections)];
   memset(unallocated_connections, false, sizeof(unallocated_connections));

   for (int i = net->next_avail_connection; i != OUT_OF_CONNECTIONS; i = net->connections[i].next) {
      unallocated_connections[i] = true;
   }

   for (int i = 0; i < ARRAY_LEN(net->connections); ++i) {
      if (!unallocated_connections[i]) {
         release_connection(net, i);
      }
   }

   closesocket(net->listen_socket);
}

static void net_accept(Networking *net) {
   net->accepted_socket = socket(AF_INET, SOCK_STREAM, 0);
   BOOL success = net->accept_ex(
      net->listen_socket, net->accepted_socket, net->accept_buf, 0, SIMULO_NET_ADDRESS_LEN,
      SIMULO_NET_ADDRESS_LEN, NULL, &net->overlapped
   );

   if (!success) {
      int err = WSAGetLastError();
      SIMULO_DEBUG_ASSERT(err == ERROR_IO_PENDING, "Abnormal error from AcceptEx: %d", err);
   }
}

bool net_listen(Networking *net) {
   if (listen(net->listen_socket, 16) == SOCKET_ERROR) {
      fprintf(stderr, "error: listen returned %d", WSAGetLastError());
      return false;
   }

   HANDLE listen_port = CreateIoCompletionPort(
      (HANDLE)net->listen_socket, net->root_completion_port, LISTENER_COMPLETION_KEY, 0
   );

   if (listen_port == NULL) {
      fprintf(stderr, "error: CreateIOCompletionPort returned %lu", GetLastError());
      return false;
   }

   net_accept(net);
   return true;
}

static void net_read(Networking *net, Connection *conn) {
   WSABUF buf;
   buf.buf = (CHAR *)&conn->login.buf[conn->login.buf_used];
   buf.len = sizeof(conn->login.buf) - conn->login.buf_used;

   DWORD flags = 0;
   int result =
      WSARecv(conn->socket, &buf, 1, NULL, &flags, &conn->login.overlapped.overlapped, NULL);

   if (result == SOCKET_ERROR) {
      int err = WSAGetLastError();
      SIMULO_DEBUG_ASSERT(err == ERROR_IO_PENDING, "err = %d", err);
   }
}

// `conn.overlapped_.op` MUST be set to a writing value before calling this
static void
net_write(Networking *net, Connection *conn, const unsigned char *data, const unsigned int len) {
   SIMULO_DEBUG_ASSERT(
      conn->login.overlapped.operation == OpWriteHandshake, "expected writing op but got %d",
      (int)conn->login.overlapped.operation
   );

   WSABUF buf;
   // Buffer is read-only- safe to cast away const
   buf.buf = (CHAR *)data;
   buf.len = len;

   conn->login.buf_used = len;

   int result = WSASend(conn->socket, &buf, 1, NULL, 0, &conn->login.overlapped.overlapped, NULL);
   if (result == SOCKET_ERROR) {
      int err = WSAGetLastError();
      SIMULO_DEBUG_ASSERT(err == ERROR_IO_PENDING, "err = %d", err);
   }
}

static void handle_accept(Networking *net, const bool success) {
   if (!success) {
      SIMULO_DEBUG_LOG("Failed to accept %llu: %lu", net->accepted_socket, GetLastError());
      close_or_log_error(net->accepted_socket);
      return;
   }

   if (net->next_avail_connection == OUT_OF_CONNECTIONS) {
      SIMULO_DEBUG_LOG("Out of connection objects for %llu", net->accepted_socket);
      close_or_log_error(net->accepted_socket);
      return;
   }

   int key = net->next_avail_connection;
   Connection *conn = &net->connections[key];
   net->next_avail_connection = conn->next;

   memset(conn, 0, sizeof(Connection));
   conn->socket = net->accepted_socket;
   conn->login.target_buf_len = 1;
   net->accepted_socket = INVALID_SOCKET;

   HANDLE client_completion_port =
      CreateIoCompletionPort((HANDLE)conn->socket, net->root_completion_port, (ULONG_PTR)key, 0);

   if (client_completion_port == NULL) {
      SIMULO_DEBUG_LOG(
         "Failed to create completion port for %llu: %lu", conn->socket, GetLastError()
      );

      release_connection(net, key);
      return;
   }

   net_read(net, conn);
   net_accept(net);
}

static void handle_read_handshake(Networking *net, int connection_key, Connection *conn) {
   Handshake handshake = {};
   int min_remaining_bytes =
      remaining_handshake_bytes(conn->login.buf, conn->login.buf_used, &handshake);
   switch (min_remaining_bytes) {
   case -1:
      SIMULO_DEBUG_LOG("Couldn't read handshake from %llu", conn->socket);
      release_connection(net, connection_key);
      break;

   case 0:
      SIMULO_DEBUG_ASSERT(
         handshake.username_len > 0 && handshake.username_len <= 16, "username len = %d",
         handshake.username_len
      );
      conn->login.target_buf_len = LOGIN_PACKET_SIZE(handshake.username_len);

      conn->login.overlapped.operation = OpWriteHandshake;
      net_write(net, conn, OFFLINE_MODE_RESPONSE, sizeof(OFFLINE_MODE_RESPONSE));
      break;

   default:
      SIMULO_DEBUG_ASSERT(
         min_remaining_bytes > 0 && min_remaining_bytes <= sizeof(conn->login.buf),
         "remaining = %d", min_remaining_bytes
      );

      conn->login.target_buf_len += (unsigned int)min_remaining_bytes;
      SIMULO_DEBUG_ASSERT(
         conn->login.target_buf_len <= sizeof(conn->login.buf), "target=%d",
         conn->login.target_buf_len
      );

      net_read(net, conn);
      break;
   }
}

static void handle_read_login(Networking *net, int connection_key, Connection *conn) {
   Login login_packet = {};
   bool ok = read_login_pkt(conn->login.buf, conn->login.buf_used, &login_packet);
   if (!ok) {
      SIMULO_DEBUG_LOG("Couldn't read login from %llu", conn->socket);
      release_connection(net, connection_key);
      return;
   }

   if (login_packet.protocol_version != BETA173_PROTOCOL_VER) {
      SIMULO_DEBUG_LOG(
         "Invalid protocol version from %llu: %d", conn->socket, login_packet.protocol_version
      );
      release_connection(net, connection_key);
      return;
   }

   if (net->num_accepted >= SIMULO_JOIN_QUEUE_CAPACITY) {
      SIMULO_DEBUG_LOG("Couldn't accept %llu because join queue is full", conn->socket);
      release_connection(net, connection_key);
      return;
   }

   char username[16];
   for (int i = 0; i < login_packet.username_len; ++i) {
      username[i] = (char)login_packet.username[i];
   }

   if (login_packet.username_len < 16) {
      username[login_packet.username_len] = '\0';
   }

   IncomingConnection *inc = &net->accepted_connections[net->num_accepted++];
   inc->conn = conn;
   memcpy(inc->username, username, sizeof(inc->username));
}

static void
handle_read(Networking *net, const bool op_success, const int connection_key, const DWORD len) {
   Connection *conn = &net->connections[connection_key];

   if (!op_success) {
      SIMULO_DEBUG_LOG("Read failed for %lld: %lu", conn->socket, GetLastError());
      release_connection(net, connection_key);
   }

   if (len < 1) {
      SIMULO_DEBUG_LOG("EOF from %lld", conn->socket);
      release_connection(net, connection_key);
      return;
   }

   SIMULO_DEBUG_ASSERT(
      len + (DWORD)conn->login.buf_used <= sizeof(conn->login.buf), "conn=%d, len=%lu, used=%d",
      connection_key, len, conn->login.buf_used
   );

   conn->login.buf_used += len;
   if (conn->login.buf_used < conn->login.target_buf_len) {
      net_read(net, conn);
      return;
   }

   switch (conn->login.overlapped.operation) {
   case OpReadHandshake:
      handle_read_handshake(net, connection_key, conn);
      break;

   case OpReadLogin:
      handle_read_login(net, connection_key, conn);
      break;

   default:
      SIMULO_PANIC("invalid op %d", (int)conn->login.overlapped.operation);
   }
}

static void
handle_write(Networking *net, const bool op_success, const int connection_key, const DWORD len) {
   Connection *conn = &net->connections[connection_key];

   if (!op_success) {
      SIMULO_DEBUG_LOG("Write failed for %llu: %lu", conn->socket, GetLastError());
      release_connection(net, connection_key);
   }

   // Although not official, WSASend has never been observed to partially complete unless the socket
   // loses connection. Keep things simple by asserting that the operation should fully complete.
   if (len < conn->login.buf_used) {
      SIMULO_DEBUG_LOG(
         "Only wrote %lu bytes to %llu instead of %d", len, conn->socket, conn->login.buf_used
      );
      release_connection(net, connection_key);
      return;
   }

   conn->login.overlapped.operation = OpReadLogin;
   conn->login.buf_used = 0;
   net_read(net, conn);
}

int net_poll(Networking *net) {
   net->num_accepted = 0;

   DWORD len;
   ULONG_PTR completion_key;
   WSAOVERLAPPED *overlapped;

   while (true) {
      BOOL op_success = GetQueuedCompletionStatus(
         net->root_completion_port, &len, &completion_key, &overlapped, 0
      );

      bool no_more_completions = overlapped == NULL;
      if (no_more_completions) {
         break;
      }

      bool accepted_new_connection = completion_key == LISTENER_COMPLETION_KEY;
      if (accepted_new_connection) {
         handle_accept(net, op_success);
      } else {
         OverlappedWithOp *with_op = (OverlappedWithOp *)overlapped;
         int conn_key = (int)completion_key;

         switch (with_op->operation) {
         case OpReadHandshake:
         case OpReadLogin:
            handle_read(net, op_success, conn_key, len);
            break;

         case OpWriteHandshake:
            handle_write(net, op_success, conn_key, len);
            break;

         default:
            SIMULO_PANIC("op = %d", (int)with_op->operation);
         }
      }
   }

   return net->num_accepted;
}
