const std = @import("std");

pub const Point = struct {
    x: i16,
    y: i16,
    on_curve: bool,
};

pub const Glyph = struct {
    bbox: struct {
        x_min: i16,
        y_min: i16,
        x_max: i16,
        y_max: i16,
    },
    end_pts: []u16,
    instructions: []u8,
    points: []Point,

    pub fn deinit(self: *Glyph, allocator: std.mem.Allocator) void {
        allocator.free(self.end_pts);
        allocator.free(self.instructions);
        allocator.free(self.points);
    }
};
