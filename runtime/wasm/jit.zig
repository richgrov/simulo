const std = @import("std");

const allocation = @import("allocate.zig");
const assembly = @import("asm.zig");

fn foo() callconv(.C) void {
    std.debug.print("Hello, world!\n", .{});
}

pub fn jit() void {
    const buffer = allocation.allocateExecutable(64) catch unreachable;
    assembly.writeAssembly(buffer);
    allocation.finishAllocation(buffer, 64);
    const func: *const fn (x: *const fn () callconv(.C) void, y: u64) callconv(.C) u64 = @alignCast(@ptrCast(buffer));
    const result = func(foo, 69);
    std.debug.print("{d}\n", .{result});
}
