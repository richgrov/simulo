const std = @import("std");
const ttf = @import("./ttf.zig");
const raster = @import("./rasterize.zig");

pub fn main() !void {
    const arial = @embedFile("../res/arial.ttf");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    const allocator = gpa.allocator();

    var font = try ttf.parse(allocator, arial);
    defer font.deinit();

    const index = try font.glyphIndex('a');
    var glyph = try ttf.parseGlyph(&font, allocator, index);
    defer glyph.deinit(allocator);

    const img = try raster.rasterizeGlyph(allocator, &glyph, 64);
    defer allocator.free(img);

    std.log.info("rasterized 'a' to {d} bytes", .{img.len});
}
