const std = @import("std");

const c = @cImport({
    @cInclude("bearssl.h");
    @cInclude("io/trustanchor.h");
});

const EventLoop = @import("event_loop.zig").EventLoop;

pub fn globalInit(allocator: std.mem.Allocator) !void {
    _ = allocator;
}

pub fn globalDeinit() void {}

fn derLen(fromStart: []const u8) !usize {
    if (fromStart.len < 2) return error.EndOfStream;
    if (fromStart[0] != 0x30) return error.InvalidCertFormat;

    const first_len_byte = fromStart[1];
    if (first_len_byte < 0x80) {
        return 2 + @as(usize, first_len_byte);
    }

    const num_bytes_for_len = first_len_byte & 0x7F;
    if (fromStart.len < 2 + num_bytes_for_len) return error.EndOfStream;

    var content_len: usize = 0;
    var i: usize = 0;
    while (i < num_bytes_for_len) : (i += 1) {
        content_len = (content_len << 8) | fromStart[2 + i];
    }

    return 2 + num_bytes_for_len + content_len;
}

pub const HttpsRequest = struct {
    ev_loop: *EventLoop,
    events: *std.ArrayList(EventLoop.EventType),
    read_in_progress: bool = false,
    write_in_progress: bool = false,
    sc: c.br_ssl_client_context = undefined,
    xc: c.br_x509_minimal_context = undefined,
    iobuf: [32 * 1024]u8 = undefined,
    state: ?struct {
        fd: std.c.fd_t,
    } = null,
    id: u32,

    pub fn init(ev_loop: *EventLoop, events: *std.ArrayList(EventLoop.EventType), id: u32, hostname: [:0]const u8) !HttpsRequest {
        var self: HttpsRequest = .{
            .ev_loop = ev_loop,
            .events = events,
            .id = id,
        };
        c.br_ssl_client_init_full(&self.sc, &self.xc, &c.TAs, c.TAs_NUM);
        c.br_ssl_engine_set_buffer(&self.sc.eng, &self.iobuf, self.iobuf.len, 1);
        _ = c.br_ssl_client_reset(&self.sc, hostname.ptr, 0);
        return self;
    }

    pub fn startPinned(self: *HttpsRequest, address: std.net.Address) !void {
        try self.ev_loop.connectTcp(address, self.events, self.id);
    }

    pub fn deinit(self: *const HttpsRequest) void {
        _ = self;
    }

    pub fn handleEvent(self: *HttpsRequest, event: *const EventLoop.EventType) !void {
        const eng = &self.sc.eng;
        const current_state = c.br_ssl_engine_current_state(eng);
        if (current_state & c.BR_SSL_CLOSED != 0) {
            const err = c.br_ssl_engine_last_error(eng);
            if (err != 0) {
                std.debug.print("BearSSL error: {d}\n", .{err});
                return error.BearSslError;
            }
        }

        switch (event.*) {
            .connect_complete => |ev| {
                self.state = .{ .fd = ev.fd };
            },
            .read_complete => |ev| {
                self.read_in_progress = false;
                if (ev.bytes_read == 0) return error.EndOfStream;
                std.debug.print("read {d} bytes\n", .{ev.bytes_read});
                c.br_ssl_engine_recvrec_ack(eng, ev.bytes_read);
            },
            .write_complete => |ev| {
                self.write_in_progress = false;
                c.br_ssl_engine_sendrec_ack(eng, ev.bytes_written);
                std.debug.print("wrote {d} bytes\n", .{ev.bytes_written});
            },
            .err => |err| {
                return err.code;
            },
            else => unreachable,
        }

        const sendrec = current_state & c.BR_SSL_SENDREC != 0;
        const sendapp = current_state & c.BR_SSL_SENDAPP != 0;
        const recvrec = current_state & c.BR_SSL_RECVREC != 0;
        const recvapp = current_state & c.BR_SSL_RECVAPP != 0;
        std.debug.print("state: sendrec={any} sendapp={any} recvrec={any} recvapp={any}\n", .{ sendrec, sendapp, recvrec, recvapp });
    }

    pub fn poll(self: *HttpsRequest) !void {
        const fd = if (self.state) |s| s.fd else return;
        const state = c.br_ssl_engine_current_state(&self.sc.eng);

        if (state & c.BR_SSL_SENDREC != 0 and !self.write_in_progress) {
            var len: usize = undefined;
            const buf = c.br_ssl_engine_sendrec_buf(&self.sc.eng, &len);
            std.debug.print("writing {d} bytes\n", .{len});
            if (len > 0) {
                const slice: []const u8 = buf[0..len];
                try self.ev_loop.startWriteFile(fd, slice, self.events);
                self.write_in_progress = true;
            }
        }

        if (state & c.BR_SSL_RECVREC != 0 and !self.read_in_progress) {
            var len: usize = undefined;
            const buf = c.br_ssl_engine_recvrec_buf(&self.sc.eng, &len);
            std.debug.print("reading {d} bytes\n", .{len});
            if (len > 0) {
                const slice: []u8 = buf[0..len];
                try self.ev_loop.startReadSocket(fd, slice, self.events);
                self.read_in_progress = true;
            }
        }

        if (state & c.BR_SSL_CLOSED != 0) {
            const err = c.br_ssl_engine_last_error(&self.sc.eng);
            if (err != 0) {
                std.debug.print("BearSSL error: {d}\n", .{err});
                return error.BearSslError;
            }
        }
    }
};

test "fetch google.com" {
    var ev_loop = try EventLoop.init(std.testing.allocator);
    defer ev_loop.deinit();

    var events = try std.ArrayList(EventLoop.EventType).initCapacity(std.testing.allocator, 16);
    defer events.deinit(std.testing.allocator);

    try globalInit(std.testing.allocator);
    defer globalDeinit();

    var client = try HttpsRequest.init(
        &ev_loop,
        &events,
        0,
        "api.simulo.tech",
    );
    defer client.deinit();
    try client.startPinned(std.net.Address.initIp4([_]u8{ 15, 204, 83, 51 }, 443));

    const start = std.time.milliTimestamp();
    while (std.time.milliTimestamp() - start < 5000) {
        try ev_loop.poll();
        for (events.items) |*event| {
            try client.handleEvent(event);
        }
        try client.poll();
        events.clearRetainingCapacity();
        std.Thread.sleep(1 * std.time.ns_per_ms);
    }

    @panic("request timed out");
}
