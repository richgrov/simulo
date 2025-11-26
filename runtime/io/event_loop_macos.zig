const std = @import("std");
const util = @import("util");
const Slab = util.Slab;
const posixErrToAnyErr = util.error_util.posixErrToAnyErr;
const c = @cImport({
    @cInclude("time.h");
    @cInclude("sys/event.h");
    @cInclude("sys/socket.h");
});
const c_unistd = @cImport(@cInclude("unistd.h"));

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

const Operation = union {
    read: ReadContext,
    write: WriteContext,
    timer: TimerContext,
};

const TimerContext = struct {
    id: usize,
};

const ReadContext = struct {
    fd: std.c.fd_t,
    buffer: []u8,
    is_file: bool,
};

const WriteContext = union(enum) {
    write: struct {
        fd: std.c.fd_t,
        buffer: []const u8,
    },
    connect: struct {
        fd: std.c.fd_t,
    },
};

const Context = struct {
    events: *std.ArrayList(EventType),
    op: Operation,
};

pub const EventLoop = struct {
    kqueue_fd: std.c.fd_t,
    allocator: std.mem.Allocator,
    slab: Slab(Context),

    pub const OpenMode = enum {
        read_only,
        write_only,
        read_write,
    };

    pub fn init(allocator: std.mem.Allocator) !EventLoop {
        const kq = c.kqueue();
        if (kq == -1) {
            return error.KQueueInitFailed;
        }
        errdefer _ = c_unistd.close(kq);

        var slab = try Slab(Context).init(allocator, 16);
        errdefer slab.deinit();

        return EventLoop{
            .kqueue_fd = kq,
            .allocator = allocator,
            .slab = slab,
        };
    }

    pub fn deinit(self: *EventLoop) void {
        if (self.kqueue_fd != -1) {
            _ = c_unistd.close(self.kqueue_fd);
        }
        self.slab.deinit();
    }

    pub fn openFile(self: *EventLoop, path: [:0]const u8, events: *std.ArrayList(EventType), mode: OpenMode) !void {
        _ = self;
        // macOS doesn't support opening files asynchronously. Prod is all linux, so this
        // performance cost is acceptable.
        const flags: std.posix.O = switch (mode) {
            .read_only => .{ .ACCMODE = .RDONLY },
            .write_only => .{ .ACCMODE = .WRONLY },
            .read_write => .{ .ACCMODE = .RDWR },
        };

        const fd = std.posix.open(path, flags, 0) catch |err| {
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

    pub fn connectTcp(self: *EventLoop, address: std.net.Address, events: *std.ArrayList(EventType)) !void {
        const sock_flags = std.posix.SOCK.STREAM | std.posix.SOCK.NONBLOCK | std.posix.SOCK.CLOEXEC;
        const fd = try std.posix.socket(address.any.family, sock_flags, std.posix.IPPROTO.TCP);
        errdefer std.posix.close(fd);

        std.posix.connect(fd, &address.any, address.getOsSockLen()) catch |err| {
            if (err == error.WouldBlock) {
                // Connection in progress, register for write event
                const context = Context{
                    .events = events,
                    .op = .{
                        .write = .{
                            .connect = .{
                                .fd = fd,
                            },
                        },
                    },
                };

                const index, _ = try self.slab.insert(context);

                const change_event = c.struct_kevent{
                    .ident = @as(c_uint, @intCast(fd)),
                    .filter = c.EVFILT_WRITE,
                    .flags = c.EV_ADD | c.EV_ENABLE | c.EV_ONESHOT,
                    .fflags = 0,
                    .data = 0,
                    .udata = @ptrFromInt(index),
                };

                const changelist = [_]c.struct_kevent{change_event};
                const nevents = c.kevent(self.kqueue_fd, &changelist, changelist.len, null, 0, null);
                if (nevents == -1) {
                    self.slab.delete(index) catch unreachable;
                    return error.KQueueEventAddFailed;
                }
                return;
            }
            return err;
        };

        // If connect returned immediately
        try events.appendBounded(.{
            .connect_complete = .{
                .fd = fd,
            },
        });
    }

    fn startReadFd(self: *EventLoop, fd: std.c.fd_t, buffer: []u8, events: *std.ArrayList(EventType), is_file: bool) !void {
        const context = Context{
            .events = events,
            .op = .{
                .read = .{
                    .fd = fd,
                    .buffer = buffer,
                    .is_file = is_file,
                },
            },
        };

        const index, _ = try self.slab.insert(context);

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
            self.slab.delete(index) catch unreachable;
            return error.KQueueEventAddFailed;
        }
    }

    pub fn startWriteFile(self: *EventLoop, fd: std.c.fd_t, buffer: []const u8, events: *std.ArrayList(EventType)) !void {
        const context = Context{
            .events = events,
            .op = .{
                .write = .{
                    .write = .{
                        .fd = fd,
                        .buffer = buffer,
                    },
                },
            },
        };

        const index, _ = try self.slab.insert(context);

        const change_event = c.struct_kevent{
            .ident = @as(c_uint, @intCast(fd)),
            .filter = c.EVFILT_WRITE,
            .flags = c.EV_ADD | c.EV_ENABLE | c.EV_ONESHOT,
            .fflags = 0,
            .data = 0,
            .udata = @ptrFromInt(index),
        };

        const changelist = [_]c.struct_kevent{change_event};
        const nevents = c.kevent(self.kqueue_fd, &changelist, changelist.len, null, 0, null);
        if (nevents == -1) {
            self.slab.delete(index) catch unreachable;
            return error.KQueueEventAddFailed;
        }
    }

    pub fn startTimer(self: *EventLoop, delay_ms: u64, id: usize, events: *std.ArrayList(EventType)) !void {
        const context = Context{
            .events = events,
            .op = .{
                .timer = .{
                    .id = id,
                },
            },
        };

        const index, _ = try self.slab.insert(context);

        const change_event = c.struct_kevent{
            .ident = @as(c_uint, @intCast(index)),
            .filter = c.EVFILT_TIMER,
            .flags = c.EV_ADD | c.EV_ENABLE | c.EV_ONESHOT,
            .fflags = c.NOTE_USECONDS,
            .data = @as(isize, @intCast(delay_ms * 1000)),
            .udata = @ptrFromInt(index),
        };

        const changelist = [_]c.struct_kevent{change_event};
        const nevents = c.kevent(self.kqueue_fd, &changelist, changelist.len, null, 0, null);
        if (nevents == -1) {
            self.slab.delete(index) catch unreachable;
            return error.KQueueEventAddFailed;
        }
    }

    pub fn startReadFile(self: *EventLoop, fd: std.c.fd_t, buffer: []u8, events: *std.ArrayList(EventType)) !void {
        try self.startReadFd(fd, buffer, events, true);
    }

    pub fn startReadSocket(self: *EventLoop, fd: std.c.fd_t, buffer: []u8, events: *std.ArrayList(EventType)) !void {
        try self.startReadFd(fd, buffer, events, false);
    }

    pub fn closeFile(self: *EventLoop, fd: std.c.fd_t) void {
        _ = self;
        _ = c_unistd.close(fd);
    }

    pub fn startCloseFile(self: *EventLoop, fd: std.c.fd_t, events: *std.ArrayList(EventType)) !void {
        _ = self;
        std.posix.close(fd);

        try events.appendBounded(.{
            .close_complete = .{
                .fd = fd,
            },
        });
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
            const index = @intFromPtr(event.udata);

            if (self.slab.get(index)) |context| {
                if (event.filter == c.EVFILT_READ) {
                    const read_ctx = context.op.read;
                    const buffer = read_ctx.buffer;

                    const bytes_read = std.posix.read(fd, buffer) catch |err| {
                        if (err != error.WouldBlock) {
                            try context.events.appendBounded(.{
                                .err = .{
                                    .fd = fd,
                                    .error_code = err,
                                },
                            });
                            // Cleanup slab on error
                            self.slab.delete(index) catch unreachable;
                        }
                        continue;
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

                        var is_eof = false;
                        if (event.flags & c.EV_EOF != 0) {
                            // If EV_EOF is set, we are at EOF if we consumed everything available
                            // kqueue reports remaining bytes in data. If we read >= data, we are done.
                            if (bytes_read >= event.data) {
                                is_eof = true;
                            }
                        } else if (read_ctx.is_file) {
                            // For regular files, kqueue stops firing when offset == size.
                            // So if we read exactly what was remaining, we must signal EOF now.
                            if (bytes_read == @as(usize, @intCast(event.data))) {
                                is_eof = true;
                            }
                        }

                        if (is_eof) {
                            try context.events.appendBounded(.{
                                .read_complete = .{
                                    .fd = fd,
                                    .data = &[_]u8{},
                                    .bytes_read = 0,
                                },
                            });
                            self.slab.delete(index) catch unreachable;
                        }
                    } else {
                        // 0 bytes read usually means EOF for sockets (if we got here)
                        // or just empty read.
                        try context.events.appendBounded(.{
                            .read_complete = .{
                                .fd = fd,
                                .data = &[_]u8{},
                                .bytes_read = 0,
                            },
                        });
                        self.slab.delete(index) catch unreachable;
                    }
                } else if (event.filter == c.EVFILT_WRITE) {
                    switch (context.op.write) {
                        .write => |write_ctx| {
                            const buffer = write_ctx.buffer;

                            const bytes_written = std.posix.write(fd, buffer) catch |err| {
                                if (err != error.WouldBlock) {
                                    try context.events.appendBounded(.{
                                        .err = .{
                                            .fd = fd,
                                            .error_code = err,
                                        },
                                    });
                                    self.slab.delete(index) catch unreachable;
                                }
                                continue;
                            };

                            try context.events.appendBounded(.{
                                .write_complete = .{
                                    .fd = fd,
                                    .bytes_written = bytes_written,
                                },
                            });
                            self.slab.delete(index) catch unreachable;
                        },
                        .connect => |connect_ctx| {
                            const fd_conn = connect_ctx.fd;
                            var err_code: i32 = 0;
                            var len: c.socklen_t = @sizeOf(i32);
                            const ret = c.getsockopt(fd_conn, c.SOL_SOCKET, c.SO_ERROR, &err_code, &len);

                            if (ret != 0) {
                                try context.events.appendBounded(.{
                                    .err = .{ .fd = fd_conn, .error_code = error.SocketOptionFailed },
                                });
                            } else if (err_code != 0) {
                                try context.events.appendBounded(.{
                                    .err = .{ .fd = fd_conn, .error_code = posixErrToAnyErr(@enumFromInt(err_code)) },
                                });
                            } else {
                                try context.events.appendBounded(.{
                                    .connect_complete = .{ .fd = fd_conn },
                                });
                            }
                            self.slab.delete(index) catch unreachable;
                        },
                    }
                } else if (event.filter == c.EVFILT_TIMER) {
                    try context.events.appendBounded(.{
                        .timer_complete = .{
                            .id = context.op.timer.id,
                        },
                    });
                    self.slab.delete(index) catch unreachable;
                }
            }
        }
    }
};
