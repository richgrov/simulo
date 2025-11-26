const std = @import("std");
const util = @import("util");
const Slab = util.Slab;
const posixErrToAnyErr = util.error_util.posixErrToAnyErr;
const c = @cImport({
    @cInclude("liburing.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
    @cInclude("errno.h");
});

pub const EventType = union(enum) {
    read_complete: ReadCompleteEvent,
    write_complete: WriteCompleteEvent,
    open_complete: OpenCompleteEvent,
    connect_complete: ConnectCompleteEvent,
    close_complete: CloseCompleteEvent,
    timer_complete: TimerCompleteEvent,
    err: ErrorEvent,
};

pub const CloseCompleteEvent = struct {
    fd: std.c.fd_t,
};

pub const TimerCompleteEvent = struct {
    id: usize,
};

pub const ConnectCompleteEvent = struct {
    fd: std.c.fd_t,
};

pub const ReadCompleteEvent = struct {
    fd: std.c.fd_t,
    data: []const u8,
    bytes_read: usize,
};

pub const WriteCompleteEvent = struct {
    fd: std.c.fd_t,
    bytes_written: usize,
};

pub const OpenCompleteEvent = struct {
    fd: std.c.fd_t,
    path: []const u8,
};

pub const ErrorEvent = struct {
    fd: ?std.c.fd_t,
    error_code: anyerror,
};

const Operation = union(enum) {
    read: ReadContext,
    write: WriteContext,
    open: OpenContext,
    close: CloseContext,
    connect: ConnectContext,
    timer: TimerContext,
};

const TimerContext = struct {
    id: usize,
    ts: *c.struct___kernel_timespec,
};

const ReadContext = struct {
    fd: std.c.fd_t,
    buffer: []u8,
};

const WriteContext = struct {
    fd: std.c.fd_t,
    buffer: []const u8,
};

const OpenContext = struct {
    path: [:0]u8,
};

const CloseContext = struct {
    fd: std.c.fd_t,
};

const ConnectContext = struct {
    fd: std.c.fd_t,
    addr: *std.net.Address,
};

const Context = struct {
    events: *std.ArrayList(EventType),
    op: Operation,
};

pub const EventLoop = struct {
    ring: c.io_uring,
    allocator: std.mem.Allocator,
    slab: Slab(Context),

    pub const OpenMode = enum {
        read_only,
        write_only,
        read_write,
    };

    pub fn init(allocator: std.mem.Allocator) !EventLoop {
        var ring: c.io_uring = undefined;
        const ret = c.io_uring_queue_init(32, &ring, 0);
        if (ret != 0) {
            return error.IoUringInitFailed;
        }
        errdefer c.io_uring_queue_exit(&ring);

        var slab = try Slab(Context).init(allocator, 32);
        errdefer slab.deinit();

        return EventLoop{
            .ring = ring,
            .allocator = allocator,
            .slab = slab,
        };
    }

    pub fn deinit(self: *EventLoop) void {
        c.io_uring_queue_exit(&self.ring);
        // We need to free any owned paths in the slab
        // But since we can't easily iterate active items in this Slab implementation
        // we might leak the paths if deinit is called while operations are pending.
        // For this task, we assume the loop is drained or it's process exit.
        // However, we should at least deinit the slab structure.
        self.slab.deinit();
    }

    pub fn openFile(self: *EventLoop, path: [:0]const u8, events: *std.ArrayList(EventType), mode: OpenMode) !void {
        const path_dupe = try self.allocator.dupeZ(u8, path);
        errdefer self.allocator.free(path_dupe);

        const context = Context{
            .events = events,
            .op = .{ .open = .{ .path = path_dupe } },
        };

        const index, _ = try self.slab.insert(context);

        const sqe = c.io_uring_get_sqe(&self.ring);
        if (sqe == null) {
            self.slab.delete(index) catch unreachable;
            return error.SubmissionQueueFull;
        }

        const flags: c_int = switch (mode) {
            .read_only => c.O_RDONLY,
            .write_only => c.O_WRONLY,
            .read_write => c.O_RDWR,
        };

        c.io_uring_prep_openat(sqe, c.AT_FDCWD, path_dupe.ptr, flags, 0);
        c.io_uring_sqe_set_data(sqe, @ptrFromInt(index));
    }

    pub fn connectTcp(self: *EventLoop, address: std.net.Address, events: *std.ArrayList(EventType)) !void {
        const sock_flags = std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC;
        const fd = try std.posix.socket(address.any.family, sock_flags, std.posix.IPPROTO.TCP);
        errdefer std.posix.close(fd);

        const addr_ptr = try self.allocator.create(std.net.Address);
        addr_ptr.* = address;
        errdefer self.allocator.destroy(addr_ptr);

        const context = Context{
            .events = events,
            .op = .{ .connect = .{ .fd = fd, .addr = addr_ptr } },
        };

        const index, _ = try self.slab.insert(context);

        const sqe = c.io_uring_get_sqe(&self.ring);
        if (sqe == null) {
            self.slab.delete(index) catch unreachable;
            return error.SubmissionQueueFull;
        }

        c.io_uring_prep_connect(sqe, fd, @ptrCast(&addr_ptr.any), addr_ptr.getOsSockLen());
        c.io_uring_sqe_set_data(sqe, @ptrFromInt(index));
    }

    pub fn startTimer(self: *EventLoop, delay_ms: u64, id: usize, events: *std.ArrayList(EventType)) !void {
        const sec = delay_ms / 1000;
        const nsec = (delay_ms % 1000) * 1000000;

        const ts_ptr = try self.allocator.create(c.struct___kernel_timespec);
        ts_ptr.* = .{
            .tv_sec = @intCast(sec),
            .tv_nsec = @intCast(nsec),
        };
        errdefer self.allocator.destroy(ts_ptr);

        const context = Context{
            .events = events,
            .op = .{
                .timer = .{
                    .id = id,
                    .ts = ts_ptr,
                },
            },
        };

        const index, _ = try self.slab.insert(context);

        const sqe = c.io_uring_get_sqe(&self.ring);
        if (sqe == null) {
            self.slab.delete(index) catch unreachable;
            return error.SubmissionQueueFull;
        }

        // Use the heap-allocated pointer which is stable
        c.io_uring_prep_timeout(sqe, ts_ptr, 0, 0);
        c.io_uring_sqe_set_data(sqe, @ptrFromInt(index));
    }

    pub fn startReadFile(self: *EventLoop, fd: std.c.fd_t, buffer: []u8, events: *std.ArrayList(EventType)) !void {
        const context = Context{
            .events = events,
            .op = .{ .read = .{ .fd = fd, .buffer = buffer } },
        };

        const index, _ = try self.slab.insert(context);

        try self.submitRead(index, fd, buffer);
    }

    pub fn startReadSocket(self: *EventLoop, fd: std.c.fd_t, buffer: []u8, events: *std.ArrayList(EventType)) !void {
        try self.startReadFile(fd, buffer, events);
    }

    fn submitRead(self: *EventLoop, index: usize, fd: std.c.fd_t, buffer: []u8) !void {
        const sqe = c.io_uring_get_sqe(&self.ring);
        if (sqe == null) {
            // If we can't submit, we have a problem.
            // If this is a re-submission, the context is already in the slab.
            // We should probably error out or handle backpressure.
            // For now, return error.
            return error.SubmissionQueueFull;
        }

        c.io_uring_prep_read(sqe, fd, buffer.ptr, @intCast(buffer.len), 0);
        c.io_uring_sqe_set_data(sqe, @ptrFromInt(index));
    }

    pub fn startWriteFile(self: *EventLoop, fd: std.c.fd_t, buffer: []const u8, events: *std.ArrayList(EventType)) !void {
        const context = Context{
            .events = events,
            .op = .{ .write = .{ .fd = fd, .buffer = buffer } },
        };

        const index, _ = try self.slab.insert(context);

        const sqe = c.io_uring_get_sqe(&self.ring);
        if (sqe == null) {
            self.slab.delete(index) catch unreachable;
            return error.SubmissionQueueFull;
        }

        c.io_uring_prep_write(sqe, fd, buffer.ptr, @intCast(buffer.len), @bitCast(@as(i64, -1)));
        c.io_uring_sqe_set_data(sqe, @ptrFromInt(index));
    }

    pub fn startCloseFile(self: *EventLoop, fd: std.c.fd_t, events: *std.ArrayList(EventType)) !void {
        const context = Context{
            .events = events,
            .op = .{ .close = .{ .fd = fd } },
        };

        const index, _ = try self.slab.insert(context);

        const sqe = c.io_uring_get_sqe(&self.ring);
        if (sqe == null) {
            self.slab.delete(index) catch unreachable;
            return error.SubmissionQueueFull;
        }

        c.io_uring_prep_close(sqe, fd);
        c.io_uring_sqe_set_data(sqe, @ptrFromInt(index));
    }

    pub fn closeFile(self: *EventLoop, fd: std.c.fd_t) void {
        _ = self;
        _ = c.close(fd);
    }

    pub fn poll(self: *EventLoop) !void {
        const submitted = c.io_uring_submit(&self.ring);
        if (submitted < 0) {
            return error.SubmitFailed;
        }

        var cqe: ?*c.io_uring_cqe = null;
        while (c.io_uring_peek_cqe(&self.ring, &cqe) == 0) {
            defer c.io_uring_cqe_seen(&self.ring, cqe.?);

            const index = @as(usize, cqe.?.user_data);
            const res = cqe.?.res;

            if (self.slab.get(index)) |context| {
                switch (context.op) {
                    .open => |*open_ctx| {
                        defer self.allocator.free(open_ctx.path);

                        if (res < 0) {
                            const err_code = posixErrToAnyErr(std.posix.errno(res));
                            try context.events.appendBounded(.{
                                .err = .{
                                    .fd = null,
                                    .error_code = err_code,
                                },
                            });
                        } else {
                            try context.events.appendBounded(.{
                                .open_complete = .{
                                    .fd = @intCast(res),
                                    .path = open_ctx.path,
                                },
                            });
                        }
                        // Open is one-shot, always remove
                        self.slab.delete(index) catch unreachable;
                    },
                    .close => |close_ctx| {
                        if (res < 0) {
                            const err_code = posixErrToAnyErr(std.posix.errno(res));
                            try context.events.appendBounded(.{
                                .err = .{
                                    .fd = close_ctx.fd,
                                    .error_code = err_code,
                                },
                            });
                        } else {
                            try context.events.appendBounded(.{
                                .close_complete = .{
                                    .fd = close_ctx.fd,
                                },
                            });
                        }
                        self.slab.delete(index) catch unreachable;
                    },
                    .read => |read_ctx| {
                        if (res < 0) {
                            const err = std.posix.errno(res);
                            // If canceled (likely due to close), just stop
                            if (err != .CANCELED and err != .BADF) {
                                try context.events.appendBounded(.{
                                    .err = .{
                                        .fd = read_ctx.fd,
                                        .error_code = posixErrToAnyErr(err),
                                    },
                                });
                            }
                            self.slab.delete(index) catch unreachable;
                        } else if (res == 0) {
                            // EOF
                            try context.events.appendBounded(.{
                                .read_complete = .{
                                    .fd = read_ctx.fd,
                                    .data = &[_]u8{},
                                    .bytes_read = 0,
                                },
                            });
                            self.slab.delete(index) catch unreachable;
                        } else {
                            // Data read
                            const bytes_read = @as(usize, @intCast(res));
                            try context.events.appendBounded(.{
                                .read_complete = .{
                                    .fd = read_ctx.fd,
                                    .data = read_ctx.buffer[0..bytes_read],
                                    .bytes_read = bytes_read,
                                },
                            });

                            // Resubmit read
                            // If resubmission fails, we should probably report error or stop.
                            self.submitRead(index, read_ctx.fd, read_ctx.buffer) catch |err| {
                                try context.events.appendBounded(.{
                                    .err = .{
                                        .fd = read_ctx.fd,
                                        .error_code = err,
                                    },
                                });
                                self.slab.delete(index) catch unreachable;
                            };
                        }
                    },
                    .write => |write_ctx| {
                        if (res < 0) {
                            const err = std.posix.errno(res);
                            if (err != .CANCELED and err != .BADF) {
                                try context.events.appendBounded(.{
                                    .err = .{
                                        .fd = write_ctx.fd,
                                        .error_code = posixErrToAnyErr(err),
                                    },
                                });
                            }
                        } else {
                            try context.events.appendBounded(.{
                                .write_complete = .{
                                    .fd = write_ctx.fd,
                                    .bytes_written = @intCast(res),
                                },
                            });
                        }
                        self.slab.delete(index) catch unreachable;
                    },
                    .connect => |*connect_ctx| {
                        defer self.allocator.destroy(connect_ctx.addr);
                        if (res < 0) {
                            const err_code = posixErrToAnyErr(std.posix.errno(res));
                            try context.events.appendBounded(.{
                                .err = .{
                                    .fd = connect_ctx.fd,
                                    .error_code = err_code,
                                },
                            });
                        } else {
                            try context.events.appendBounded(.{
                                .connect_complete = .{
                                    .fd = connect_ctx.fd,
                                },
                            });
                        }
                        self.slab.delete(index) catch unreachable;
                    },
                    .timer => |timer_ctx| {
                        defer self.allocator.destroy(timer_ctx.ts);
                        if (res == -@as(i32, @intCast(c.ETIME))) {
                            // Timeout expired successfully
                            try context.events.appendBounded(.{
                                .timer_complete = .{
                                    .id = timer_ctx.id,
                                },
                            });
                        } else if (res < 0) {
                            // Canceled or other error
                            // We treat generic timeout errors as just completion or ignored if canceled?
                            // Usually -ETIME is success for timeout operation.
                            // Other errors might be cancellation.
                            const err = std.posix.errno(res);
                            if (err != .CANCELED) {
                                try context.events.appendBounded(.{
                                    .err = .{
                                        .fd = null, // No FD for timer
                                        .error_code = posixErrToAnyErr(err),
                                    },
                                });
                            }
                        } else {
                            // Should be -ETIME usually?
                            // "This system call returns 0 if the timeout expired" -> Wait, io_uring_prep_timeout?
                            // man io_uring_prep_timeout:
                            // "If the timeout expires, the CQE result will be -ETIME."
                            // "If count is 0, the timeout will expire when the time is up."

                            // Wait, if I used count=0, it triggers on timeout.
                            // Result is -ETIME.

                            // Let's handle 0 as success too just in case.
                            try context.events.appendBounded(.{
                                .timer_complete = .{
                                    .id = timer_ctx.id,
                                },
                            });
                        }
                        self.slab.delete(index) catch unreachable;
                    },
                }
            }
        }
    }
};
