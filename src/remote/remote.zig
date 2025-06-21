const std = @import("std");
const download = @import("./download.zig");

pub const Remote = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Remote {
        return Remote{ .allocator = allocator };
    }

    pub fn fetchProgram(self: *Remote, url: []const u8) !void {
        return download.download(url, self.allocator);
    }
};
