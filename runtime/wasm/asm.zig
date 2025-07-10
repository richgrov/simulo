const builtin = @import("builtin");

const aarch64 = @import("asm_aarch64.zig");
const Error = @import("error.zig").Error;
const Module = @import("deserializer.zig").Module;

pub fn writeAssembly(target: *anyopaque, module: *const Module) !?Error {
    return switch (builtin.target.cpu.arch) {
        .aarch64 => aarch64.writeAssembly(target, module),
        else => @compileError("unsupported architecture"),
    };
}
