const std = @import("std");

const Detection = @import("inference/inference.zig").Detection;

pub fn writeMoveEvent(writer: *std.io.Writer, id: u64, det: *const Detection, width: f32, height: f32) !void {
    try writer.writeInt(u8, 0, .big);
    try writer.writeInt(u32, @intCast(id), .big);
    for (det.keypoints) |kp| {
        try writer.writeInt(i16, @intFromFloat(kp.pos[0] * width), .big);
        try writer.writeInt(i16, @intFromFloat(kp.pos[1] * height), .big);
    }
}

pub fn writeLostEvent(writer: *std.io.Writer, id: u64) !void {
    try writer.writeInt(u8, 1, .big);
    try writer.writeInt(u32, @intCast(id), .big);
}

pub fn writeResizeEvent(writer: *std.io.Writer, width: u16, height: u16) !void {
    try writer.writeInt(u8, 2, .big);
    try writer.writeInt(u16, width, .big);
    try writer.writeInt(u16, height, .big);
}
