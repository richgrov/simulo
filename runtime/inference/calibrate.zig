const std = @import("std");

const DMat3 = @import("engine").math.DMat3;

const WIDTH = 640;
const HEIGHT = 480;
const RGB_FRAME = HEIGHT * WIDTH * 3;

const ffi = @cImport({
    @cInclude("ffi.h");
});

fn debugSaveImage(image: []u8) void {
    const file = std.fs.cwd().createFile("image.bin", .{}) catch unreachable;
    defer file.close();
    file.writeAll(image) catch unreachable;
}

pub const Calibrator = struct {
    background_frame: [RGB_FRAME]u8 = undefined,
    calibration_frames: [2]*ffi.OpenCvMat,
    transform: DMat3 = undefined,

    pub fn init() Calibrator {
        return .{
            .calibration_frames = [2]*ffi.OpenCvMat{
                ffi.create_opencv_mat(HEIGHT, WIDTH).?,
                ffi.create_opencv_mat(HEIGHT, WIDTH).?,
            },
        };
    }

    pub fn deinit(self: *Calibrator) void {
        ffi.destroy_opencv_mat(self.calibration_frames[0]);
        ffi.destroy_opencv_mat(self.calibration_frames[1]);
    }

    pub fn buffers(self: *Calibrator) [2][*]u8 {
        return [2][*]u8{
            ffi.get_opencv_mat_data(self.calibration_frames[0]),
            ffi.get_opencv_mat_data(self.calibration_frames[1]),
        };
    }

    pub fn setBackground(self: *Calibrator, frame: *[RGB_FRAME]u8) void {
        @memcpy(&self.background_frame, frame);
    }

    pub fn calibrate(self: *Calibrator, frame_idx: usize, chessboard_width: i32, chessboard_height: i32, transform_out: *DMat3) bool {
        var transform_mat: ffi.FfiMat3 = undefined;
        if (ffi.find_chessboard(self.calibration_frames[frame_idx], chessboard_width, chessboard_height, &transform_mat)) {
            transform_out.* = DMat3.fromRowMajorPtr(&transform_mat.data);
            return true;
        }
        return false;
    }
};
