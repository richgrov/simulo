const std = @import("std");
const builtin = @import("builtin");

const ffi = @cImport({
    @cInclude("ffi.h");
});

pub const MacOsCamera = struct {
    camera: ffi.Camera,

    pub fn init() !MacOsCamera {
        var camera = ffi.Camera{};
        const success = ffi.init_camera(&camera);
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

    pub inline fn getFrame(self: *MacOsCamera) ?*const u8 {
        return ffi.get_camera_frame(&self.camera);
    }
};
