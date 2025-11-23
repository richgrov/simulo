const std = @import("std");
const util = @import("util");
const Slab = util.Slab;
const posixErrToAnyErr = util.error_util.posixErrToAnyErr;
const c = @cImport({
    @cInclude("liburing.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
});

pub const EventType = union(enum) {
    read_complete: ReadCompleteEvent,
    open_complete: OpenCompleteEvent,
    err: ErrorEvent,
};

pub const ReadCompleteEvent = struct {
    fd: std.c.fd_t,
    data: []const u8,
    bytes_read: usize,
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
    open: OpenContext,
};

const ReadContext = struct {
    fd: std.c.fd_t,
    buffer: []u8,
};

const OpenContext = struct {
    path: [:0]u8,
};

const Context = struct {
    events: *std.ArrayList(EventType),
    op: Operation,
};

pub const EventLoop = struct {
    ring: c.io_uring,
    allocator: std.mem.Allocator,
    slab: Slab(Context),

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

    pub fn openFile(self: *EventLoop, path: [:0]const u8, events: *std.ArrayList(EventType)) !void {
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

        c.io_uring_prep_openat(sqe, c.AT_FDCWD, path_dupe.ptr, c.O_RDONLY, 0);
        c.io_uring_sqe_set_data(sqe, @ptrFromInt(index));
    }

    pub fn startRead(self: *EventLoop, fd: std.c.fd_t, buffer: []u8, events: *std.ArrayList(EventType)) !void {
        const context = Context{
            .events = events,
            .op = .{ .read = .{ .fd = fd, .buffer = buffer } },
        };

        const index, _ = try self.slab.insert(context);

        try self.submitRead(index, fd, buffer);
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
                }
            }
        }
    }
};
