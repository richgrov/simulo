const std = @import("std");
const builtin = @import("builtin");

const aarch64 = @import("asm_aarch64.zig");
const Module = @import("deserializer.zig").Module;

pub const CompiledModule = switch (builtin.target.cpu.arch) {
    .aarch64 => aarch64.CompiledModule,
    else => @compileError("unsupported architecture"),
};

pub fn writeAssembly(target: []u8, module: *const Module, allocator: std.mem.Allocator) !CompiledModule {
    return switch (builtin.target.cpu.arch) {
        .aarch64 => aarch64.writeAssembly(target, module, allocator),
        else => @compileError("unsupported architecture"),
    };
}
