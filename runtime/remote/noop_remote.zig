const std = @import("std");
const packet = @import("./packet.zig");
const Packet = packet.Packet;

pub const NoOpRemote = struct {
    pub fn init(_: *NoOpRemote, _: std.mem.Allocator) !void {}

    pub fn deinit(_: *NoOpRemote) void {}

    pub fn sendPing(_: *NoOpRemote) void {}

    pub fn sendProfile(_: *NoOpRemote, _: []const u8, _: anytype, _: anytype) void {}

    pub fn nextMessage(_: *NoOpRemote) ?Packet {
        return null;
    }

    pub fn fetch(_: *NoOpRemote, _: []const u8, _: *const [32]u8, _: []const u8) !void {}
};

