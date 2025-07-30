const std = @import("std");
const builtin = @import("builtin");

const aarch64 = @import("asm_aarch64.zig");
const Module = @import("deserializer.zig").Module;

pub const CompileResult = switch (builtin.target.cpu.arch) {
    .aarch64 => aarch64.CompileResult,
    else => @compileError("unsupported architecture"),
};

pub fn writeAssembly(target: *anyopaque, module: *const Module, allocator: std.mem.Allocator) CompileResult {
    return switch (builtin.target.cpu.arch) {
        .aarch64 => aarch64.writeAssembly(target, module, allocator),
        else => @compileError("unsupported architecture"),
    };
}
