const std = @import("std");

const DMat3 = @import("engine").math.DMat3;

const WIDTH = 640;
const HEIGHT = 480;
const RGB_FRAME = HEIGHT * WIDTH * 3;

const opencv = @import("../opencv/opencv.zig");
const Mat = opencv.Mat;

fn debugSaveImage(image: []u8) void {
    const file = std.fs.cwd().createFile("image.bin", .{}) catch unreachable;
    defer file.close();
    file.writeAll(image) catch unreachable;
}

pub const Calibrator = struct {
    background_frame: [RGB_FRAME]u8 = undefined,
    calibration_frames: [2]Mat,
    transform: DMat3 = undefined,

    pub fn init() !Calibrator {
        return Calibrator{
            .calibration_frames = [2]Mat{
                try Mat.init(HEIGHT, WIDTH, opencv.c.Type8UC3),
                try Mat.init(HEIGHT, WIDTH, opencv.c.Type8UC3),
            },
        };
    }

    pub fn deinit(self: *Calibrator) void {
        self.calibration_frames[0].deinit();
        self.calibration_frames[1].deinit();
    }

    pub fn buffers(self: *Calibrator) [2][*]u8 {
        return [2][*]u8{
            self.calibration_frames[0].data(),
            self.calibration_frames[1].data(),
        };
    }

    pub fn setBackground(self: *Calibrator, frame: *[RGB_FRAME]u8) void {
        @memcpy(&self.background_frame, frame);
    }

    pub fn calibrate(self: *Calibrator, frame_idx: usize, chessboard_width: i32, chessboard_height: i32) !?DMat3 {
        return self.calibration_frames[frame_idx].findChessboardTransform(
            chessboard_width,
            chessboard_height,
            opencv.c.CalibCbExhaustive,
        );
    }
};
