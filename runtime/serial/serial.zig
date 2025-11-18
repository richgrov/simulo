pub const builtin = @import("builtin");

pub const Serial = switch (builtin.os.tag) {
    .macos, .linux => @import("serial_posix.zig").Serial,
    else => @compileError("unsupported OS for serial"),
};
