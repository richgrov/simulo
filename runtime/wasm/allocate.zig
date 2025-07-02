const builtin = @import("builtin");

const allocate_macos = @import("allocate_macos.zig");

pub fn allocateExecutable(len: usize) !*anyopaque {
    return switch (comptime builtin.os.tag) {
        .macos => allocate_macos.allocateExecutable(len),
        else => @compileError("unsupported platform"),
    };
}

pub fn finishAllocation(ptr: *anyopaque, len: usize) void {
    switch (comptime builtin.os.tag) {
        .macos => allocate_macos.finishAllocation(ptr, len),
        else => @compileError("unsupported platform"),
    }
}
