const std = @import("std");
const builtin = @import("builtin");

pub const reflect = @import("reflect.zig");
pub const vulkan = @import("platform.zig").vulkan;

pub const Slab = @import("slab.zig").Slab;
pub const CheckedSlab = @import("checked_slab.zig").CheckedSlab;
pub const FixedArrayList = @import("fixed_arraylist.zig").FixedArrayList;
pub const IntSet = @import("int_set.zig").IntSet;
pub const SparseIntSet = @import("packed_set.zig").SparseIntSet;
pub const Spsc = @import("spsc_ring.zig").Spsc;

pub const error_util = @import("error_util.zig");
pub const crash = @import("crash.zig");

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
        _ = CheckedSlab;
        _ = FixedArrayList;
        _ = IntSet;
        _ = SparseIntSet;
        _ = Spsc;
        _ = error_util;
    }
}
