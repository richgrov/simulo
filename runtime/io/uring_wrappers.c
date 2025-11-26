#include <liburing.h>

struct io_uring_sqe *zig_io_uring_get_sqe(struct io_uring *ring) {
    return io_uring_get_sqe(ring);
}

int zig_io_uring_peek_cqe(struct io_uring *ring, struct io_uring_cqe **cqe_ptr) {
    return io_uring_peek_cqe(ring, cqe_ptr);
}

void zig_io_uring_cqe_seen(struct io_uring *ring, struct io_uring_cqe *cqe) {
    io_uring_cqe_seen(ring, cqe);
}
