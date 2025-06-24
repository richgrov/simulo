const std = @import("std");
const util = @import("util");
const websocket = @import("websocket");

const Spsc = util.Spsc;
const download = @import("./download.zig");

pub const Remote = struct {
    const LogEntry = struct {
        buf: [512]u8,
        used: usize,
    };

    allocator: std.mem.Allocator,
    id: []const u8,
    secret_key: std.crypto.sign.Ed25519.KeyPair,
    websocket_cli: websocket.Client,
    ws_read_thread: ?std.Thread = null,
    ws_write_thread: ?std.Thread = null,
    running: bool = true,
    log_queue: Spsc(LogEntry, 256),

    pub fn init(allocator: std.mem.Allocator, id: []const u8, private_key: *[32]u8) !Remote {
        if (id.len > 64) {
            return error.InvalidId;
        }

        if (private_key.len != 32) {
            return error.InvalidPrivateKey;
        }

        const key_pair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(private_key.*);

        return Remote{
            .allocator = allocator,
            .id = id,
            .secret_key = key_pair,
            .websocket_cli = try websocket.Client.init(allocator, .{
                .host = "localhost",
                .port = 3001,
                //.tls = true,
            }),
            .log_queue = Spsc(LogEntry, 256).init(),
        };
    }

    pub fn deinit(self: *Remote) void {
        @atomicStore(bool, &self.running, false, .seq_cst);
        if (self.ws_write_thread) |thread| {
            thread.join();
        }
        self.websocket_cli.deinit();
        if (self.ws_read_thread) |thread| {
            thread.join();
        }
    }

    pub fn start(self: *Remote) !void {
        try self.websocket_cli.handshake("/", .{
            .timeout_ms = 5000,
            .headers = "Host: localhost:9224",
        });

        self.ws_read_thread = try self.websocket_cli.readLoopInNewThread(self);
        self.ws_write_thread = try std.Thread.spawn(.{}, Remote.writeLoop, .{self});

        const signature = try self.secret_key.sign(self.id, null);
        const signature_bytes = signature.toBytes();

        // auth message:
        // id_length: u8
        // id: [id_length]u8
        // signature: [signature_bytes.len]u8
        var message: [1 + 64 + signature_bytes.len]u8 = undefined;
        message[0] = @intCast(self.id.len);
        @memcpy(message[1 .. 1 + self.id.len], self.id);
        @memcpy(message[1 + self.id.len .. 1 + self.id.len + signature_bytes.len], &signature_bytes);
        try self.websocket_cli.writeBin(message[0 .. 1 + self.id.len + signature_bytes.len]);
    }

    pub fn log(self: *Remote, comptime fmt: []const u8, args: anytype) void {
        var log_entry = LogEntry{
            .buf = undefined,
            .used = undefined,
        };

        const msg = std.fmt.bufPrintZ(&log_entry.buf, fmt, args) catch |err| {
            std.log.err("couldn't format log message: {any}", .{err});
            return;
        };
        log_entry.used = msg.len;

        std.log.info("{s}", .{msg});
        self.log_queue.enqueue(log_entry) catch {
            std.log.err("log queue is full for {s}", .{msg});
        };
    }

    fn writeLoop(self: *Remote) void {
        while (@atomicLoad(bool, &self.running, .monotonic)) {
            while (self.log_queue.tryDequeue()) |log_entry| {
                var entry = log_entry;
                const msg = entry.buf[0..entry.used];
                self.websocket_cli.writeText(msg) catch |err| {
                    std.log.err("couldn't write log message '{s}': {any}", .{ msg, err });
                };
            }

            std.time.sleep(std.time.ns_per_ms * 100);
        }
        std.log.info("remote write loop has exited", .{});
    }

    pub fn serverMessage(self: *Remote, data: []u8, ty: websocket.MessageTextType) !void {
        _ = self;
        _ = ty;
        std.debug.print("Received message: {s}\n", .{data});
    }

    pub fn serverClose(self: *Remote, data: []u8) !void {
        if (data.len >= 2) {
            const codeCodeHi: u16 = @intCast(data[0]);
            const codeCodeLo: u16 = @intCast(data[1]);
            const closeCode = codeCodeHi << 8 | codeCodeLo;
            const closeReason = data[2..];
            std.debug.print("Websocket closed: {d}: {s}\n", .{ closeCode, closeReason });
        }

        try self.websocket_cli.close(.{});
    }

    pub fn fetchProgram(self: *Remote, url: []const u8) !void {
        return download.download(url, self.allocator);
    }
};
