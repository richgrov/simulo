const std = @import("std");

var data_dir_buf: [128]u8 = undefined;
var data_dir: ?[]const u8 = null;

pub fn globalInit(allocator: std.mem.Allocator) !void {
    const home_dir = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home_dir);

    data_dir = try std.fmt.bufPrint(&data_dir_buf, "{s}/.simulo", .{home_dir});
}

pub fn getFilePath(buf: []u8, name: []const u8) std.fmt.BufPrintError![]const u8 {
    return std.fmt.bufPrint(buf, "{s}/{s}", .{ data_dir.?, name });
}
