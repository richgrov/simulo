const std = @import("std");

const opencv = @cImport({
    @cInclude("image/opencv_image.h");
});

pub const ImageInfo = struct {
    width: i32,
    height: i32,
    data: []const u8,
    _image_data: ?*opencv.ImageData,
    
    pub fn deinit(self: *ImageInfo) void {
        if (self._image_data) |img_data| {
            opencv.free_image_data(img_data);
            self._image_data = null;
        }
    }
};

pub fn loadImage(data: []const u8) !ImageInfo {
    const image_data = opencv.load_image_from_memory(data.ptr, @intCast(data.len));
    if (image_data == null) {
        return error.FailedToLoadImage;
    }

    const width = opencv.get_image_width(image_data);
    const height = opencv.get_image_height(image_data);
    const image_bytes = opencv.get_image_data(image_data);
    
    return .{
        .width = width,
        .height = height,
        .data = image_bytes[0..@intCast(width * height * 4)],
        ._image_data = image_data,
    };
}
