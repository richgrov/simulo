import socket
import sys


def run_server(port):
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server_socket.bind(("127.0.0.1", port))
        server_socket.listen(1)
        print(f"Listening on port {port}")
        sys.stdout.flush()

        conn, addr = server_socket.accept()
        print(f"Connected by {addr}")

        data = conn.recv(1024)
        if not data:
            print("No data received")
        else:
            print(f"Received: {data.decode('utf-8')}")
            conn.sendall(b"Ack: " + data)

        conn.close()
    except Exception as e:
        print(f"Error: {e}")
    finally:
        server_socket.close()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 test_tcp.py <port>")
        sys.exit(1)

    port = int(sys.argv[1])
    run_server(port)
