const std = @import("std");

const allocation = @import("allocate.zig");
const assembly = @import("asm.zig");

pub fn jit() void {
    const buffer = allocation.allocateExecutable(64) catch unreachable;
    assembly.writeAssembly(buffer);
    allocation.finishAllocation(buffer, 64);
    const func: *const fn () callconv(.C) u64 = @alignCast(@ptrCast(buffer));
    const result = func();
    std.debug.print("{d}\n", .{result});
}
