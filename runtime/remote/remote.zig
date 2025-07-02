const std = @import("std");
const build_options = @import("build_options");

const util = @import("util");
const websocket = @import("websocket");

const Spsc = util.Spsc;
const download = @import("./download.zig");

pub const Remote = struct {
    pub const LogEntry = struct {
        buf: [512]u8,
        used: usize,
    };

    allocator: std.mem.Allocator,
    id: []const u8,
    secret_key: std.crypto.sign.Ed25519.KeyPair,

    host: []const u8,
    port: u16,
    tls: bool,

    websocket_cli: ?websocket.Client = null,
    client_lock: std.Thread.RwLock.DefaultRwLock = .{},
    ws_conn_thread: ?std.Thread = null,
    ws_read_thread: ?std.Thread = null,
    ws_write_thread: ?std.Thread = null,

    running: bool = true,
    authenticated: bool = false,
    log_queue: Spsc(LogEntry, 256),
    inbound_queue: Spsc(LogEntry, 128),

    pub fn init(allocator: std.mem.Allocator, id: []const u8, private_key: *const [32]u8) !Remote {
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
            .host = build_options.api_host,
            .port = build_options.api_port,
            .tls = build_options.api_tls,
            .websocket_cli = null,
            .log_queue = Spsc(LogEntry, 256).init(),
            .inbound_queue = Spsc(LogEntry, 128).init(),
        };
    }

    pub fn deinit(self: *Remote) void {
        @atomicStore(bool, &self.running, false, .seq_cst);
        if (self.ws_conn_thread) |thread| {
            thread.join();
        }
        if (self.ws_write_thread) |thread| {
            thread.join();
        }
        if (self.websocket_cli) |*ws| {
            ws.deinit();
        }
    }

    pub fn start(self: *Remote) !void {
        self.ws_write_thread = try std.Thread.spawn(.{}, Remote.writeLoop, .{self});
        self.ws_conn_thread = try std.Thread.spawn(.{}, Remote.connectionLoop, .{self});
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
            std.time.sleep(std.time.ns_per_ms * 100);

            if (!@atomicLoad(bool, &self.authenticated, .acquire)) {
                continue;
            }

            self.client_lock.lockShared();
            defer self.client_lock.unlockShared();
            const ws = if (self.websocket_cli) |*cli| cli else continue;

            while (self.log_queue.tryDequeue()) |log_entry| {
                var entry = log_entry;
                const msg = entry.buf[0..entry.used];
                ws.writeText(msg) catch |err| {
                    std.log.err("couldn't write log message '{s}': {any}", .{ msg, err });
                };
            }
        }
        std.log.info("remote write loop has exited", .{});
    }

    fn connectionLoop(self: *Remote) void {
        var backoff_ms: u64 = 1000;
        const max_backoff_ms: u64 = 16000;

        while (@atomicLoad(bool, &self.running, .monotonic)) {
            @atomicStore(bool, &self.authenticated, false, .release);

            self.tryConnect() catch |err| {
                std.log.err("could not connect: {any}", .{err});
                std.time.sleep(std.time.ns_per_ms * backoff_ms);
                backoff_ms = @min(backoff_ms * 2, max_backoff_ms);
                continue;
            };

            backoff_ms = 1000;

            if (self.ws_read_thread) |thread| {
                thread.join();
                self.ws_read_thread = null;
            }
        }
    }

    fn tryConnect(self: *Remote) !void {
        var ws = try websocket.Client.init(self.allocator, .{
            .host = self.host,
            .port = self.port,
            .tls = self.tls,
        });
        errdefer ws.deinit();

        try ws.handshake("/", .{
            .timeout_ms = 5000,
            .headers = "Host: localhost:9224",
        });

        self.ws_read_thread = try ws.readLoopInNewThread(self);

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
        try ws.writeBin(message[0 .. 1 + self.id.len + signature_bytes.len]);

        self.client_lock.lock();
        defer self.client_lock.unlock();
        self.websocket_cli = ws;
    }

    pub fn serverMessage(self: *Remote, data: []u8, ty: websocket.MessageTextType) !void {
        if (ty != .text) {
            return;
        }

        if (data.len > 512) {
            std.log.err("message '{s}' too large ({x})", .{ data, data.len });
            return;
        }

        @atomicStore(bool, &self.authenticated, true, .release);
        var entry: LogEntry = undefined;
        entry.used = data.len;
        @memcpy(entry.buf[0..data.len], data);
        self.inbound_queue.enqueue(entry) catch |err| {
            std.log.err("couldn't enqueue message '{s}': {any}", .{ data, err });
        };
    }

    pub fn serverClose(self: *Remote, data: []u8) !void {
        if (data.len >= 2) {
            const codeCodeHi: u16 = @intCast(data[0]);
            const codeCodeLo: u16 = @intCast(data[1]);
            const closeCode = codeCodeHi << 8 | codeCodeLo;
            const closeReason = data[2..];
            std.debug.print("Websocket closed: {d}: {s}\n", .{ closeCode, closeReason });
        }

        @atomicStore(bool, &self.authenticated, false, .release);

        if (self.websocket_cli) |*ws| {
            try ws.close(.{});
            ws.deinit();
            self.websocket_cli = null;
        }
    }

    pub fn nextMessage(self: *Remote) ?LogEntry {
        return self.inbound_queue.tryDequeue();
    }

    pub fn fetchProgram(self: *Remote, url: []const u8) !void {
        return download.download(url, self.allocator);
    }
};
