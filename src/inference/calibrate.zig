const std = @import("std");

const WIDTH = 640;
const HEIGHT = 480;
const FRAME = HEIGHT * WIDTH;
const RGB_FRAME = FRAME * 3;

fn debugSaveImage(image: []u8) void {
    const file = std.fs.cwd().createFile("image.bin", .{}) catch unreachable;
    defer file.close();
    file.writeAll(image) catch unreachable;
}

fn basicBinaryThreshold(rgb: *[RGB_FRAME]u8, threshold: u8, out: *[FRAME]u8) void {
    for (0..FRAME) |i| {
        const r = rgb[i * 3];
        const g = rgb[i * 3 + 1];
        const b = rgb[i * 3 + 2];
        out[i] = if (r > threshold or g > threshold or b > threshold) 255 else 0;
    }
}

const Contour = struct {
    start: usize,
    paths: [2048]Relative,
};

const Relative = enum(u8) {
    right,
    down_right,
    down,
    down_left,
    left,
    up_left,
    up,
    up_right,
};

fn findContour(binary: *[FRAME]u8, min_perimeter: usize, out: *Contour) bool {
    out.start = std.math.maxInt(usize);
    for (0..FRAME) |i| {
        if (binary[i] != 0) {
            out.start = i;
            break;
        }
    }

    if (out.start == std.math.maxInt(usize)) {
        return false;
    }

    var contour_index: usize = 0;
    var pixel_index = out.start;
    while (contour_index < out.paths.len) {
        const x = pixel_index % WIDTH;
        const y = pixel_index / WIDTH;
        const not_top_edge = y > 0;
        const not_left_edge = x > 0;
        const not_right_edge = x < WIDTH - 1;
        const not_bottom_edge = y < HEIGHT - 1;

        if (not_right_edge and binary[pixel_index + 1] != 0) {
            out.paths[contour_index] = Relative.right;
            pixel_index += 1;
        } else if (not_right_edge and not_bottom_edge and binary[pixel_index + WIDTH + 1] != 0) {
            out.paths[contour_index] = Relative.down_right;
            pixel_index += WIDTH + 1;
        } else if (not_bottom_edge and binary[pixel_index + WIDTH] != 0) {
            out.paths[contour_index] = Relative.down;
            pixel_index += WIDTH;
        } else if (not_bottom_edge and not_left_edge and binary[pixel_index + WIDTH - 1] != 0) {
            out.paths[contour_index] = Relative.down_left;
            pixel_index += WIDTH - 1;
        } else if (not_left_edge and binary[pixel_index - 1] != 0) {
            out.paths[contour_index] = Relative.left;
            pixel_index -= 1;
        } else if (not_left_edge and not_top_edge and binary[pixel_index - WIDTH - 1] != 0) {
            out.paths[contour_index] = Relative.up_left;
            pixel_index -= WIDTH - 1;
        } else if (not_top_edge and binary[pixel_index - WIDTH] != 0) {
            out.paths[contour_index] = Relative.up;
            pixel_index -= WIDTH;
        } else if (not_top_edge and not_right_edge and binary[pixel_index - WIDTH + 1] != 0) {
            out.paths[contour_index] = Relative.up_right;
            pixel_index -= WIDTH - 1;
        }

        contour_index += 1;
    }

    return contour_index >= min_perimeter;
}

pub const Calibrator = struct {
    background_frame: [RGB_FRAME]u8 = undefined,

    pub fn init() Calibrator {
        return .{};
    }

    pub fn setBackground(self: *Calibrator, frame: *[RGB_FRAME]u8) void {
        @memcpy(&self.background_frame, frame);
    }

    pub fn calibrate(self: *Calibrator, frame: *[RGB_FRAME]u8) void {
        for (0..RGB_FRAME) |i| {
            frame[i] -|= self.background_frame[i];
        }

        var thresholded: [FRAME]u8 = undefined;
        basicBinaryThreshold(frame, 128, &thresholded);
    }
};
