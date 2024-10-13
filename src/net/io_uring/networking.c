#include "networking.h"

#include <errno.h>
#include <liburing.h>
#include <netinet/in.h>
#include <stdbool.h>
#include <stdio.h>
#include <sys/socket.h>
#include <unistd.h>

static inline bool enable_reuseaddr(int fd) {
   int value = 1;
   int res = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &value, sizeof(value));
   return res == 0;
}

static inline void queue_accept(Networking *net) {
   struct io_uring_sqe *sqe = io_uring_get_sqe(&net->ring);
   io_uring_prep_accept(sqe, net->fd, (struct sockaddr *)&net->address, &net->address_size, 0);
   sqe->user_data = 12;
}

bool net_init(Networking *net, uint16_t port, IncomingConnection *accepted_connections) {
   struct sockaddr_in address = {
      .sin_family = AF_INET,
      .sin_port = htons(port),
      .sin_addr.s_addr = INADDR_ANY,
   };
   net->address = address;
   net->address_size = sizeof(address);

   net->fd = socket(AF_INET, SOCK_STREAM, 0);
   if (net->fd == -1) {
      fprintf(stderr, "socket returned -1: %d", errno);
      return false;
   }

   if (!enable_reuseaddr(net->fd)) {
      fprintf(stderr, "couldn't reuseaddr on %d: %d", net->fd, errno);
      return false;
   }

   if (bind(net->fd, (struct sockaddr *)&net->address, net->address_size) == -1) {
      fprintf(stderr, "couldn't bind %d: %d", net->fd, errno);
      return false;
   }

   struct io_uring_params params = {};
   // TODO: is 2048 a good amount?
   int res = io_uring_queue_init_params(2048, &net->ring, &params);
   if (res != 0) {
      fprintf(stderr, "couldn't init uring params: %d", -res);
      return false;
   }

   if (!(params.features & IORING_FEAT_FAST_POLL)) {
      fprintf(stderr, "fast poll isn't supported");
      return false;
   }

   queue_accept(net);

   return true;
}

void net_deinit(Networking *net) {
   shutdown(net->fd, SHUT_RDWR);
   close(net->fd);
}

bool net_listen(Networking *net) {
   bool ok = listen(net->fd, 16) == 0;
   if (!ok) {
      fprintf(stderr, "couldn't listen on %d: %d", net->fd, errno);
   }
   return ok;
}

int net_poll(Networking *net) {
   return 0;
}