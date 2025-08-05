const std = @import("std");
const GlyphMod = @import("./glyph.zig");
const Glyph = GlyphMod.Glyph;
const Point = GlyphMod.Point;

pub fn rasterizeGlyph(allocator: std.mem.Allocator, glyph: *const Glyph, pixels: usize) ![]u8 {
    const scale = @as(f64, pixels) / @as(f64, glyph.bbox.y_max - glyph.bbox.y_min);
    const width = pixels;
    const height = pixels;
    var img = try allocator.alloc(u8, width * height * 4);
    std.mem.set(u8, img, 0);

    for (0..height) |y| {
        const fy = @as(f64, @intCast(height - 1 - y)) / scale + glyph.bbox.y_min;
        for (0..width) |x| {
            const fx = @as(f64, @intCast(x)) / scale + glyph.bbox.x_min;
            if (pointInside(glyph, fx, fy)) {
                const idx = (y * width + x) * 4;
                img[idx] = 0xff;
                img[idx + 1] = 0xff;
                img[idx + 2] = 0xff;
                img[idx + 3] = 0xff;
            }
        }
    }
    return img;
}

fn pointInside(glyph: *const Glyph, px: f64, py: f64) bool {
    var inside = false;
    var start: usize = 0;
    for (glyph.end_pts) |end_idx| {
        var prev = glyph.points[end_idx];
        var i = start;
        while (i <= end_idx) : (i += 1) {
            const curr = glyph.points[i];
            if (((curr.y > py) != (prev.y > py)) and (px < (@as(f64, prev.x) + (py - @as(f64, prev.y)) * (@as(f64, curr.x - prev.x) / @as(f64, curr.y - prev.y))))) {
                inside = !inside;
            }
            prev = curr;
        }
        start = end_idx + 1;
    }
    return inside;
}
