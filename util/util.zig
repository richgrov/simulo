const std = @import("std");
const builtin = @import("builtin");

pub const reflect = @import("reflect.zig");
pub const vulkan = @import("platform.zig").vulkan;

pub const Slab = @import("slab.zig").Slab;
pub const FixedSlab = @import("fixed_slab.zig").FixedSlab;
pub const FixedArrayList = @import("fixed_arraylist.zig").FixedArrayList;
pub const SparseIntSet = @import("packed_set.zig").SparseIntSet;
pub const Spsc = @import("spsc_ring.zig").Spsc;

pub fn getResourcePath(name: []const u8, buf: []u8) ![]const u8 {
    var path_buf: [128]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&path_buf);

    return switch (builtin.target.os.tag) {
        // Navigate from *.app/Contents/MacOS/ to *.app/Contents/Resources/<name>
        .macos => try std.fmt.bufPrintZ(buf, "{s}/../Resources/{s}", .{ exe_dir, name }),
        .linux => try std.fmt.bufPrintZ(buf, "{s}/{s}", .{ exe_dir, name }),
        else => @compileError("platform not supported"),
    };
}

test {
    comptime {
        _ = reflect;
        _ = Slab;
        _ = FixedSlab;
        _ = FixedArrayList;
        _ = SparseIntSet;
        _ = Spsc;
    }
}
