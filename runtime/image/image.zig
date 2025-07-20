const std = @import("std");

const stb = @cImport({
    @cInclude("image/stb_image.h");
});

pub const ImageInfo = struct {
    width: i32,
    height: i32,
    data: []const u8,
};

pub fn loadImage(data: []const u8) !ImageInfo {
    stb.stbi_set_flip_vertically_on_load(1);

    var width: i32 = 0;
    var height: i32 = 0;
    var channels: i32 = 0;
    const image = stb.stbi_load_from_memory(data.ptr, @intCast(data.len), &width, &height, &channels, 4);
    if (image == null) {
        return error.FailedToLoadImage;
    }
    std.debug.assert(channels == 4);

    return .{
        .width = width,
        .height = height,
        .data = image[0..@intCast(width * height * 4)],
    };
}
