const std = @import("std");
const packet = @import("./packet.zig");
const Packet = packet.Packet;

pub const NoOpRemote = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, _: []const u8, _: *const [32]u8) !NoOpRemote {
        return NoOpRemote{
            .allocator = allocator,
        };
    }

    pub fn deinit(_: *NoOpRemote) void {}

    pub fn start(_: *NoOpRemote) !void {}

    pub fn sendPing(_: *NoOpRemote) void {}

    pub fn sendProfile(_: *NoOpRemote, _: []const u8, _: anytype, _: anytype) void {}

    pub fn nextMessage(_: *NoOpRemote) ?Packet {
        return null;
    }

    pub fn fetch(_: *NoOpRemote, _: []const u8, _: *const [32]u8, _: []const u8) !void {}
};