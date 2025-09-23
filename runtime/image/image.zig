const std = @import("std");

const opencv = @cImport({
    @cInclude("image/opencv_image.h");
});

pub const ImageInfo = struct {
    width: i32,
    height: i32,
    data: []const u8,

    pub fn deinit(self: *ImageInfo) void {
        opencv.free_image_data(@ptrCast(self.data.ptr));
    }
};

pub fn loadImage(data: []const u8) !ImageInfo {
    var out_w: c_int = 0;
    var out_h: c_int = 0;
    const bytes = opencv.load_image_from_memory(data.ptr, @intCast(data.len), &out_w, &out_h);
    if (bytes == null) {
        return error.ImageLoadFailed;
    }
    const width: i32 = @intCast(out_w);
    const height: i32 = @intCast(out_h);
    const len: usize = @intCast(width * height * 4);

    return .{
        .width = width,
        .height = height,
        .data = bytes[0..len],
    };
}
