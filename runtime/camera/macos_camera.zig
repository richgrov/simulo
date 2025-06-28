const std = @import("std");
const builtin = @import("builtin");

const ffi = @cImport({
    @cInclude("ffi.h");
});

pub const MacOsCamera = struct {
    camera: ffi.Camera,

    pub fn init(out: [2][*]u8) !MacOsCamera {
        var camera = ffi.Camera{};
        const success = ffi.init_camera(&camera, out[0], out[1]);
        if (!success) {
            return error.CameraInitFailed;
        }

        return MacOsCamera{
            .camera = camera,
        };
    }

    pub inline fn deinit(self: *MacOsCamera) void {
        ffi.destroy_camera(&self.camera);
    }

    pub inline fn setFloatMode(self: *MacOsCamera, out: [2][*]f32) void {
        ffi.set_camera_float_mode(&self.camera, out[0], out[1]);
    }

    pub inline fn swapBuffers(self: *MacOsCamera) !usize {
        return @intCast(ffi.swap_camera_buffers(&self.camera));
    }
};
