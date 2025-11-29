const std = @import("std");
const build_options = @import("build_options");
const Logger = @import("../log.zig").Logger;

const engine = @import("engine");
const profile = engine.profiler;

const util = @import("util");

const Spsc = util.Spsc;
const download = @import("./download.zig");
const packet = @import("./packet.zig");
const Packet = packet.Packet;

const MIN_RECONNECT_DELAY_MS: u64 = 1000;
const MAX_RECONNECT_DELAY_MS: u64 = 16000;

fn apiHost() []const u8 {
    const noHttps = std.mem.trimStart(u8, build_options.api_url, "https://");
    return std.mem.trimStart(u8, noHttps, "http://");
}

const fs_storage = @import("../fs_storage.zig");

fn readPrivateKey() ![32]u8 {
    var private_key_path_buf: [512]u8 = undefined;
    const private_key_path = fs_storage.getFilePath(&private_key_path_buf, "private.der") catch unreachable;

    var private_key_buf: [68]u8 = undefined;
    const private_key_der = try std.fs.cwd().readFile(private_key_path, &private_key_buf);
    if (private_key_der.len < 48) {
        return error.PrivateKeyTooShort;
    }

    var private_key: [32]u8 = undefined;
    @memcpy(&private_key, private_key_der[private_key_der.len - 32 ..]);
    return private_key;
}

pub const Remote = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    secret_key: std.crypto.sign.Ed25519.KeyPair,

    read_thread: ?std.Thread = null,
    sse_handler: SseHandler = undefined,
    running: bool = true,
    reconnect_delay_ms: u64 = MIN_RECONNECT_DELAY_MS,
    inbound_queue: Spsc(Packet, 128),
    logger: Logger("remote", 2048),

    pub fn init(self: *Remote, allocator: std.mem.Allocator) !void {
        const machine_id = std.posix.getenv("SIMULO_MACHINE_ID") orelse return error.NoMachineId;
        if (machine_id.len != 36) {
            return error.InvalidMachineId;
        }

        const private_key = try readPrivateKey();
        const key_pair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(private_key);

        self.* = Remote{
            .allocator = allocator,
            .id = machine_id,
            .secret_key = key_pair,
            .inbound_queue = Spsc(Packet, 128).init(),
            .logger = Logger("remote", 2048).init(),
        };

        self.read_thread = try std.Thread.spawn(.{}, Remote.readLoop, .{self});
    }

    pub fn deinit(self: *Remote) void {
        @atomicStore(bool, &self.running, false, .seq_cst);

        if (self.read_thread) |*thread| {
            thread.join();
        }
    }

    pub fn sendProfile(_: *Remote, _: anytype, _: []const profile.Logs) void {}

    fn readLoop(self: *Remote) void {
        while (@atomicLoad(bool, &self.running, .monotonic)) {
            var payload_buf: [64]u8 = undefined;
            const time = std.time.milliTimestamp();
            self.logger.debug("Time to be signed is {d}", .{time});
            const payload = std.fmt.bufPrint(&payload_buf, "{d}", .{time}) catch unreachable;

            const signature = self.secret_key.sign(payload, null) catch |err| {
                self.logger.err("couldn't sign payload: {any}", .{err});
                self.exponentialSleep();
                continue;
            };

            const signature_bytes = std.fmt.bytesToHex(signature.toBytes(), .lower);

            var url_buf: [1024]u8 = undefined;
            const url = std.fmt.bufPrint(
                &url_buf,
                build_options.api_url ++ "/machines/{s}/events/v1?timestamp={s}&signature={s}",
                .{
                    self.id,
                    payload,
                    signature_bytes,
                },
            ) catch unreachable;

            self.logger.info("Attempting cloud connection to {s}", .{url});
            defer self.logger.info("Closed cloud connection", .{});

            var client = std.http.Client{ .allocator = self.allocator };
            defer client.deinit();

            var sse_buf: [1024 * 16]u8 = undefined;
            self.sse_handler.init(self.allocator, &sse_buf, &Remote.onEvent);

            const response = client.fetch(.{
                .method = .GET,
                .location = .{ .url = url },
                .headers = .{ .host = .{ .override = comptime apiHost() } },
                .response_writer = &self.sse_handler.interface,
            }) catch |err| {
                self.logger.err("couldn't connect to cloud: {any}", .{err});
                self.exponentialSleep();
                continue;
            };

            if (response.status != .ok) {
                self.logger.err("couldn't connect to cloud: {s}: {s}", .{ @tagName(response.status), self.sse_handler.data.items });
                self.exponentialSleep();
                continue;
            }

            self.logger.info("Connected to cloud", .{});
        }
    }

    fn onEvent(handler: *SseHandler, data: []const u8) void {
        const self: *Remote = @fieldParentPtr("sse_handler", handler);
        @atomicStore(u64, &self.reconnect_delay_ms, MIN_RECONNECT_DELAY_MS, .seq_cst);
        if (std.mem.eql(u8, data, "keep-alive")) {
            return;
        }

        const prefix_len = ("data:").len;
        if (data.len < prefix_len) {
            self.logger.err("event data too short: {s}", .{data});
            return;
        }

        const len = std.base64.standard.Decoder.calcSizeForSlice(data[prefix_len..]) catch |err| {
            self.logger.err("message's size couldn't be calculated: {s}: {s}", .{ @errorName(err), data });
            return;
        };

        var b64_buf: [1024 * 16]u8 = undefined;
        std.base64.standard.Decoder.decode(&b64_buf, data[prefix_len..]) catch |err| {
            self.logger.err("undecodable event: {s}: {s}", .{ @errorName(err), data });
            return;
        };

        const pkt = self.parsePacket(self.allocator, b64_buf[0..len]) catch |err| {
            self.logger.err("invalid event: {s}: {x}", .{ @errorName(err), b64_buf[0..len] });
            return;
        };

        self.inbound_queue.enqueue(pkt) catch |err| {
            self.logger.err("inbound event queue is full: {s}: {x}", .{ @errorName(err), b64_buf[0..len] });
            return;
        };
    }

    fn exponentialSleep(self: *Remote) void {
        const delay = @atomicLoad(u64, &self.reconnect_delay_ms, .seq_cst);
        const new_delay = @min(delay * 2, MAX_RECONNECT_DELAY_MS);
        @atomicStore(u64, &self.reconnect_delay_ms, new_delay, .seq_cst);
        std.Thread.sleep(std.time.ns_per_ms * delay);
    }

    pub fn nextMessage(self: *Remote) ?Packet {
        return self.inbound_queue.tryDequeue();
    }

    pub fn fetch(self: *Remote, url: []const u8, hash: *const [32]u8, dest_path: []const u8) !void {
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
            try dest.seekTo(0);
            var hasher = std.crypto.hash.sha2.Sha256.init(.{});
            var buf: [64 * 1024]u8 = undefined;
            var reader = dest.reader(&.{});
            while (true) {
                const n = try reader.interface.readSliceShort(&buf);
                hasher.update(buf[0..n]);
                if (n < buf.len) break;
            }

            var hash_bytes: [32]u8 = undefined;
            hasher.final(&hash_bytes);
            if (std.mem.eql(u8, &hash_bytes, hash)) {
                self.logger.info("Hash matches, skipping download to {s}", .{dest_path});
                return;
            }
        }

        try dest.seekTo(0);
        const length = try download.download(url, dest, self.allocator);
        self.logger.debug("Downloaded {d} bytes", .{length});
        try dest.setEndPos(length);
    }

    fn parsePacket(self: *Remote, allocator: std.mem.Allocator, data: []const u8) !Packet {
        var reader = packet.Reader.init(data);
        switch (try reader.readInt(u8)) {
            0 => {
                var encountered_error = false;

                const program_url = try reader.readString(1024, allocator);
                var program_hash: [32]u8 = undefined;
                try reader.readFull(&program_hash);

                const program_path = fs_storage.getCachePathAlloc(allocator, &program_hash) catch unreachable;
                errdefer allocator.free(program_path);

                self.logger.info("Downloading program: {s} -> {s}", .{ program_url, program_path });
                self.fetch(program_url, &program_hash, program_path) catch |err| {
                    self.logger.err("program download failed: {s}", .{@errorName(err)});
                    encountered_error = true;
                };

                const num_files = try reader.readInt(u8);
                if (num_files > fs_storage.max_assets) {
                    return error.InvalidNumFiles;
                }

                const files = try allocator.alloc(fs_storage.ProgramAsset, num_files);
                errdefer allocator.free(files);
                for (files) |*file| {
                    const name = try reader.readString(fs_storage.max_asset_name_len, allocator);
                    defer allocator.free(name);
                    file.name = util.FixedArrayList(u8, fs_storage.max_asset_name_len).initFrom(name) catch unreachable;

                    const url = try reader.readString(1024, allocator);
                    defer allocator.free(url);

                    var hash: [32]u8 = undefined;
                    try reader.readFull(&hash);
                    const dest_path = fs_storage.getCachePathAlloc(allocator, &hash) catch unreachable;
                    errdefer allocator.free(dest_path);

                    self.logger.info("Downloading asset \"{s}\": {s} -> {s}", .{ name, url, dest_path });
                    self.fetch(url, &hash, dest_path) catch |err| {
                        self.logger.err("asset download failed: {s}", .{@errorName(err)});
                        encountered_error = true;
                    };

                    file.real_path = dest_path;
                }

                if (encountered_error) {
                    return error.ProgramDownloadEncounteredError;
                }

                return Packet{ .download = .{
                    .program_path = program_path,
                    .files = files,
                } };
            },
            1 => {
                const has_schedule = try reader.readInt(u8);
                if (has_schedule == 0) {
                    return Packet{ .schedule = null };
                }

                const start_ms = try reader.readInt(u64);
                const stop_ms = try reader.readInt(u64);

                return Packet{ .schedule = .{
                    .start_ms = start_ms,
                    .stop_ms = stop_ms,
                } };
            },
            else => return error.UnknownPacketId,
        }
    }
};

const SseHandler = struct {
    vtable: std.io.Writer.VTable,
    interface: std.io.Writer,
    allocator: std.mem.Allocator,
    data: std.ArrayList(u8),
    on_event: *const fn (handler: *SseHandler, data: []const u8) void,

    pub fn init(self: *SseHandler, allocator: std.mem.Allocator, buf: []u8, on_event: *const fn (handler: *SseHandler, data: []const u8) void) void {
        self.* = .{
            .vtable = std.io.Writer.VTable{
                .drain = SseHandler.drain,
            },
            .interface = .{
                .vtable = &self.vtable,
                .buffer = &[_]u8{},
            },
            .allocator = allocator,
            .data = std.ArrayList(u8).initBuffer(buf),
            .on_event = on_event,
        };
    }

    fn drain(writer: *std.io.Writer, data: []const []const u8, splat: usize) error{WriteFailed}!usize {
        const self: *SseHandler = @fieldParentPtr("interface", writer);

        var n: usize = 0;

        for (data, 0..) |chunk, i| {
            const repeat = if (i == data.len - 1) splat else 1;

            n += chunk.len * repeat;
            var previous: u8 = 0;
            for (0..repeat) |_| {
                for (chunk) |c| {
                    if (c == '\n') {
                        if (previous == '\n') {
                            self.on_event(self, self.data.items);
                            self.data.clearRetainingCapacity();
                            previous = 0;
                        } else {
                            previous = c;
                        }
                        continue;
                    } else if (previous == '\n') {
                        self.data.appendBounded('\n') catch return error.WriteFailed;
                    }

                    previous = c;
                    self.data.appendBounded(c) catch return error.WriteFailed;
                }
            }
        }

        return n;
    }
};
