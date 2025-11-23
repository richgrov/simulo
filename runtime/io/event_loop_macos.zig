const std = @import("std");
const Slab = @import("util").Slab;
const c = @cImport({
    @cInclude("time.h");
    @cInclude("sys/event.h");
});
const c_unistd = @cImport(@cInclude("unistd.h"));

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

const ReadContext = struct {
    buffer: []u8,
    events: *std.ArrayList(EventType),
    fd: std.c.fd_t,
};

pub const EventLoop = struct {
    kqueue_fd: std.c.fd_t,
    allocator: std.mem.Allocator,
    read_slab: Slab(ReadContext),

    pub fn init(allocator: std.mem.Allocator) !EventLoop {
        const kq = c.kqueue();
        if (kq == -1) {
            return error.KQueueInitFailed;
        }
        errdefer _ = c_unistd.close(kq);

        var slab = try Slab(ReadContext).init(allocator, 16);
        errdefer slab.deinit();

        return EventLoop{
            .kqueue_fd = kq,
            .allocator = allocator,
            .read_slab = slab,
        };
    }

    pub fn deinit(self: *EventLoop) void {
        if (self.kqueue_fd != -1) {
            _ = c_unistd.close(self.kqueue_fd);
        }
        self.read_slab.deinit();
    }

    pub fn openFile(self: *EventLoop, path: [:0]const u8, events: *std.ArrayList(EventType)) !void {
        _ = self;
        // macOS doesn't support opening files asynchronously. Prod is all linux, so this
        // performance cost is acceptable.
        const fd = std.posix.open(path, .{ .ACCMODE = .RDONLY }, 0) catch |err| {
            try events.appendBounded(.{
                .err = .{
                    .fd = null,
                    .error_code = err,
                },
            });
            return;
        };

        try events.appendBounded(.{
            .open_complete = .{
                .fd = fd,
                .path = path,
            },
        });
    }

    pub fn startRead(self: *EventLoop, fd: std.c.fd_t, buffer: []u8, events: *std.ArrayList(EventType)) !void {
        const context = ReadContext{
            .buffer = buffer,
            .events = events,
            .fd = fd,
        };

        const index, _ = try self.read_slab.insert(context);

        const change_event = c.struct_kevent{
            .ident = @as(c_uint, @intCast(fd)),
            .filter = c.EVFILT_READ,
            .flags = c.EV_ADD | c.EV_ENABLE,
            .fflags = 0,
            .data = 0,
            .udata = @ptrFromInt(index),
        };

        const changelist = [_]c.struct_kevent{change_event};
        const nevents = c.kevent(self.kqueue_fd, &changelist, changelist.len, null, 0, null);
        if (nevents == -1) {
            self.read_slab.delete(index) catch unreachable;
            return error.KQueueEventAddFailed;
        }
    }

    pub fn closeFile(self: *EventLoop, fd: std.c.fd_t) void {
        _ = self;
        _ = c_unistd.close(fd);
    }

    pub fn poll(self: *EventLoop) !void {
        var kevents: [32]c.struct_kevent = undefined;
        var timeout = std.mem.zeroes(c.timespec);

        const nevents = c.kevent(
            self.kqueue_fd,
            null,
            0,
            &kevents,
            kevents.len,
            &timeout,
        );

        if (nevents == -1) {
            return error.PollFailed;
        }

        for (kevents[0..@intCast(nevents)]) |event| {
            const fd = @as(std.c.fd_t, @intCast(event.ident));

            if (event.filter == c.EVFILT_READ) {
                var reached_eof = false;

                if (event.flags & c.EV_EOF != 0) {
                    reached_eof = true;
                }

                const index = @intFromPtr(event.udata);
                if (self.read_slab.get(index)) |context| {
                    if (event.data > 0 or !reached_eof) {
                        // Data available or we want to check for EOF by reading
                        const buffer = context.buffer;

                        // Loop to drain available data and check for EOF
                        while (true) {
                            const bytes_read = std.posix.read(fd, buffer) catch |err| {
                                if (err == error.WouldBlock) {
                                    break;
                                }
                                try context.events.appendBounded(.{
                                    .err = .{
                                        .fd = fd,
                                        .error_code = err,
                                    },
                                });
                                reached_eof = true; // Stop on error
                                break;
                            };

                            if (bytes_read > 0) {
                                const data_slice = buffer[0..bytes_read];
                                try context.events.appendBounded(.{
                                    .read_complete = .{
                                        .fd = fd,
                                        .data = data_slice,
                                        .bytes_read = bytes_read,
                                    },
                                });
                            } else if (bytes_read == 0) {
                                reached_eof = true;
                                break;
                            }
                        }
                    }

                    if (reached_eof) {
                        // End of file reached
                        try context.events.appendBounded(.{
                            .read_complete = .{
                                .fd = fd,
                                .data = &[_]u8{},
                                .bytes_read = 0,
                            },
                        });

                        // Cleanup slab
                        self.read_slab.delete(index) catch unreachable;
                    }
                }
            }
        }
    }
};
