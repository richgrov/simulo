const std = @import("std");

pub const MaterialProperties = struct {};

pub const Renderer = struct {
    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};
