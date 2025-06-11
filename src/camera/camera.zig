const std = @import("std");
const builtin = @import("builtin");

pub const Camera = switch (builtin.os.tag) {
    .macos => @import("macos_camera.zig").MacOsCamera,
    .linux => @import("linux_camera.zig").LinuxCamera,
    else => @compileError("Unsupported platform"),
};
