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
    background_frame: Mat,
    calibration_frames: [2]Mat,
    subtraction_buffer: Mat,
    transform: DMat3 = undefined,

    pub fn init() !Calibrator {
        var background_frame = try Mat.init(HEIGHT, WIDTH, opencv.c.Type8UC3);
        errdefer background_frame.deinit();

        var subtraction_buffer = try Mat.init(HEIGHT, WIDTH, opencv.c.Type8UC3);
        errdefer subtraction_buffer.deinit();

        return Calibrator{
            .background_frame = background_frame,
            .calibration_frames = [2]Mat{
                try Mat.init(HEIGHT, WIDTH, opencv.c.Type8UC3),
                try Mat.init(HEIGHT, WIDTH, opencv.c.Type8UC3),
            },
            .subtraction_buffer = subtraction_buffer,
        };
    }

    pub fn deinit(self: *Calibrator) void {
        self.calibration_frames[0].deinit();
        self.calibration_frames[1].deinit();
        self.background_frame.deinit();
        self.subtraction_buffer.deinit();
    }

    pub fn mats(self: *Calibrator) [2]*Mat {
        return [2]*Mat{
            &self.calibration_frames[0],
            &self.calibration_frames[1],
        };
    }

    pub fn setBackground(self: *Calibrator, frame: usize) !void {
        try self.calibration_frames[frame].copyTo(&self.background_frame);
    }

    pub fn calibrate(self: *Calibrator, frame_idx: usize, chessboard_width: i32, chessboard_height: i32) !?DMat3 {
        try self.calibration_frames[frame_idx].subtract(&self.background_frame, &self.subtraction_buffer);
        return self.subtraction_buffer.findChessboardTransform(
            chessboard_width,
            chessboard_height,
            opencv.c.CalibCbExhaustive,
        );
    }
};
