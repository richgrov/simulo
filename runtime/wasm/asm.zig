const builtin = @import("builtin");

const aarch64 = @import("asm_aarch64.zig");

pub fn writeAssembly(target: *anyopaque) void {
    return switch (builtin.target.cpu.arch) {
        .aarch64 => aarch64.writeAssembly(target),
        else => @compileError("unsupported architecture"),
    };
}
