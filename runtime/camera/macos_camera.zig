const std = @import("std");
const builtin = @import("builtin");

const Logger = @import("../log.zig").Logger;

const ffi = @cImport({
    @cInclude("camera/macos_camera.h");
});

const Mat = @import("../opencv/opencv.zig").Mat;

pub const MacOsCamera = struct {
    camera: ffi.Camera,
    logger: Logger("macos_camera", 2048),

    pub fn init(out: [2]*Mat, device_id: []const u8) !MacOsCamera {
        var logger = Logger("macos_camera", 2048).init();

        var camera = ffi.Camera{};
        const err = ffi.init_camera(&camera, out[0].data(), out[1].data(), device_id.ptr, device_id.len);
        switch (err) {
            ffi.ErrorNone => {},
            ffi.ErrorNoCamera => return error.NoCamera,
            ffi.ErrorNoPermission => return error.NoPermission,
            ffi.ErrorCannotCapture => return error.CannotCapture,
            ffi.ErrorCannotCreateCapture => return error.CannotCreateCapture,
            ffi.ErrorCannotAddInput => return error.CannotAddInput,
            ffi.ErrorCannotAddOutput => return error.CannotAddOutput,
            else => {
                logger.err("unknown camera init code: {d}", .{err});
                return error.CameraUnknownError;
            },
        }

        return MacOsCamera{
            .camera = camera,
            .logger = logger,
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
