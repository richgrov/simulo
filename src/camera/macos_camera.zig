const std = @import("std");
const builtin = @import("builtin");

const ffi = @cImport({
    @cInclude("ffi.h");
});

pub const MacOsCamera = struct {
    camera: ffi.Camera,

    pub fn init(out: []u8) !MacOsCamera {
        var camera = ffi.Camera{};
        const success = ffi.init_camera(&camera, &out[0]);
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

    pub inline fn lockFrame(self: *MacOsCamera) void {
        ffi.lock_camera_frame(&self.camera);
    }

    pub inline fn unlockFrame(self: *MacOsCamera) void {
        ffi.unlock_camera_frame(&self.camera);
    }
};
