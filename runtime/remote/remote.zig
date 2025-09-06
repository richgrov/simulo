const std = @import("std");
const build_options = @import("build_options");

const engine = @import("engine");
const profile = engine.profiler;

const util = @import("util");
const websocket = @import("websocket");

const Spsc = util.Spsc;
const download = @import("./download.zig");
const packet = @import("./packet.zig");
const Packet = packet.Packet;

const MIN_RECONNECT_DELAY_MS: u64 = 1000;
const MAX_RECONNECT_DELAY_MS: u64 = 16000;

const OutboundMessage = union(enum) {
    log: Remote.LogEntry,
    ping: void,
    profile: struct {
        name: []const u8,
        labels: profile.Labels,
        logs: []const profile.Logs,
    },
};

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
    reconnect_delay_ms: u64 = MIN_RECONNECT_DELAY_MS,
    log_queue: Spsc(OutboundMessage, 256),
    inbound_queue: Spsc(Packet, 128),

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
            .log_queue = Spsc(OutboundMessage, 256).init(),
            .inbound_queue = Spsc(Packet, 128).init(),
        };
    }

    pub fn deinit(self: *Remote) void {
        @atomicStore(bool, &self.running, false, .seq_cst);

        if (self.websocket_cli) |*ws| {
            ws.close(.{}) catch |err| {
                std.log.err("cwebsocket close error: {any}", .{err});
            };
        }

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
        var log_entry = OutboundMessage{
            .log = .{
                .buf = undefined,
                .used = undefined,
            },
        };

        const msg = std.fmt.bufPrintZ(&log_entry.log.buf, fmt, args) catch |err| {
            std.log.err("couldn't format log message: {any}", .{err});
            return;
        };
        log_entry.log.used = msg.len;

        std.log.info("{s}", .{msg});
        self.log_queue.enqueue(log_entry) catch {
            std.log.err("log queue is full for {s}", .{msg});
        };
    }

    pub fn sendPing(self: *Remote) void {
        const log_entry = OutboundMessage{
            .ping = {},
        };
        self.log_queue.enqueue(log_entry) catch {
            std.log.err("log queue is full for ping", .{});
        };
    }

    pub fn sendProfile(self: *Remote, profiler: anytype, logs: []const profile.Logs) void {
        const log_entry = OutboundMessage{
            .profile = .{
                .name = profiler.profilerName(),
                .labels = profiler.labels(),
                .logs = logs,
            },
        };

        self.log_queue.enqueue(log_entry) catch {
            std.log.err("log queue is full for profiler logs", .{});
        };
    }

    fn writeLoop(self: *Remote) void {
        while (@atomicLoad(bool, &self.running, .monotonic)) {
            std.Thread.sleep(std.time.ns_per_ms * 100);

            if (!@atomicLoad(bool, &self.authenticated, .acquire)) {
                continue;
            }

            self.client_lock.lockShared();
            defer self.client_lock.unlockShared();
            const ws = if (self.websocket_cli) |*cli| cli else continue;

            while (self.log_queue.tryDequeue()) |log_entry| {
                switch (log_entry) {
                    .log => |entry| {
                        var entry_mut = entry;
                        const msg = entry_mut.buf[0..entry_mut.used];
                        ws.writeText(msg) catch |err| {
                            std.log.err("couldn't write log message '{s}': {any}", .{ msg, err });
                        };
                    },
                    .ping => {
                        ws.writePing(&[0]u8{}) catch |err| {
                            std.log.err("couldn't write ping: {any}", .{err});
                        };
                    },
                    .profile => |profile_result| {
                        var pkt = packet.outboundProfile(profile_result.name, profile_result.labels, profile_result.logs) catch |err| {
                            comptime if (@TypeOf(err) != error{PacketTooLong}) unreachable;
                            std.log.err("profile packet was too long to serialize", .{});
                            continue;
                        };

                        ws.writeBin(pkt.bytes()) catch |err| {
                            std.log.err("couldn't write profile: {any}", .{err});
                        };
                    },
                }
            }
        }
        std.log.info("remote write loop has exited", .{});
    }

    fn connectionLoop(self: *Remote) void {
        const host = build_options.api_host;

        while (@atomicLoad(bool, &self.running, .monotonic)) {
            defer if (self.websocket_cli) |*ws| {
                ws.close(.{}) catch |err| {
                    std.log.err("couldn't close websocket: {any}", .{err});
                };
                ws.deinit();
                self.websocket_cli = null;
            };

            @atomicStore(bool, &self.authenticated, false, .release);

            std.log.info("Attempting to connect to websocket on {s}", .{host});
            self.tryConnect() catch |err| {
                std.log.err("could not connect: {any}", .{err});
                self.exponentialSleep();
                continue;
            };

            std.log.info("Connected to websocket on {s}", .{host});

            if (self.ws_read_thread) |thread| {
                thread.join();
                self.ws_read_thread = null;
            }

            std.log.info("Closed websocket {s}", .{host});
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
            .headers = "Host: " ++ build_options.api_host,
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

    fn exponentialSleep(self: *Remote) void {
        const delay = @atomicLoad(u64, &self.reconnect_delay_ms, .seq_cst);
        const new_delay = @min(delay * 2, MAX_RECONNECT_DELAY_MS);
        @atomicStore(u64, &self.reconnect_delay_ms, new_delay, .seq_cst);
        std.Thread.sleep(std.time.ns_per_ms * delay);
    }

    pub fn serverMessage(self: *Remote, data: []u8, ty: websocket.MessageTextType) !void {
        errdefer self.exponentialSleep();

        if (ty != .binary) {
            std.log.err("got invalid {any} message type", .{ty});
            return error.MessageNotBinary;
        }

        if (data.len > 8 * 1024) {
            std.log.err("message too large ({d})", .{data.len});
            return error.MessageTooLarge;
        }

        const msg = Packet.from(self.allocator, data) catch |err| {
            std.log.err("couldn't parse message: {any}", .{err});
            return error.MessageParseError;
        };

        self.inbound_queue.enqueue(msg) catch |err| {
            std.log.err("couldn't enqueue message: {any}", .{err});
            return error.MessageEnqueueError;
        };

        @atomicStore(bool, &self.authenticated, true, .release);
        @atomicStore(u64, &self.reconnect_delay_ms, MIN_RECONNECT_DELAY_MS, .seq_cst);
    }

    pub fn serverPing(self: *Remote, data: []u8) !void {
        // There is a bug in the websocket library that causes pings to corrupt the TLS connection,
        // so responding to pings is turned off for now.
        _ = self;
        _ = data;
    }

    pub fn serverClose(self: *Remote, data: []u8) !void {
        var ok = true;
        if (data.len >= 2) {
            const codeCodeHi: u16 = @intCast(data[0]);
            const codeCodeLo: u16 = @intCast(data[1]);
            const closeCode = codeCodeHi << 8 | codeCodeLo;
            const closeReason = data[2..];
            std.debug.print("Websocket closed: {d}: {s}\n", .{ closeCode, closeReason });

            if (closeCode != 1000 and closeCode != 1001) {
                ok = false;
            }
        }

        if (self.websocket_cli) |*ws| {
            try ws.close(.{});
            ws.deinit();
            self.websocket_cli = null;
        }

        if (!ok) {
            self.exponentialSleep();
        }
    }

    pub fn nextMessage(self: *Remote) ?Packet {
        return self.inbound_queue.tryDequeue();
    }

    pub fn fetch(self: *Remote, url: []const u8, hash: *const [32]u8, dest_path: []const u8) !void {
        self.log("Downloading {s} to {s}", .{ url, dest_path });

        var check_hash = true;
        const dest = std.fs.cwd().openFile(dest_path, .{ .mode = .read_write }) catch |err| file: {
            if (err == error.FileNotFound) {
                check_hash = false;
                break :file try std.fs.cwd().createFile(dest_path, .{});
            }

            return err;
        };
        defer dest.close();

        if (check_hash) {
            const content = try dest.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
            defer self.allocator.free(content);

            var hash_bytes: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(content, &hash_bytes, .{});
            if (std.mem.eql(u8, &hash_bytes, hash)) {
                self.log("Hash matches, skipping download to {s}", .{dest_path});
                return;
            }
        }

        try dest.seekTo(0);
        const length = try download.download(url, dest, self.allocator);
        try dest.setEndPos(length);
    }
};
