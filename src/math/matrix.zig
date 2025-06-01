const std = @import("std");

const vulkan = @import("../util/platform.zig").vulkan;
const Y_AXIS = if (vulkan) -1 else 1;

fn Matrix(T: type, comptime rows: usize, comptime cols: usize) type {
    return struct {
        const Self = @This();

        data: [rows]@Vector(cols, T),

        pub fn identity() Self {
            if (rows != cols) {
                @compileError("matrix must be square to produce identity");
            }

            var result = std.mem.zeroInit(Self, .{});
            for (0..rows) |i| {
                result.data[i][i] = 1.0;
            }
            return result;
        }

        pub fn ortho(width: f32, height: f32, near: f32, far: f32) Matrix(f32, 4, 4) {
            const depth = far - near;
            return .{
                .data = [_]@Vector(4, f32){
                    .{ 2.0 / width, 0, 0, 0 },
                    .{ 0, 2.0 / height, 0, 0 },
                    .{ 0, 0, 1.0 / depth, 0 },
                    .{ -1, -Y_AXIS, -near / depth, 1 },
                },
            };
        }

        pub fn scale(v: @Vector(rows - 1, f32)) Matrix(f32, rows, rows) {
            if (rows != cols) {
                @compileError("matrix must be square to scale");
            }

            return .{
                .data = [_]@Vector(rows, f32){
                    .{ v[0], 0, 0, 0 },
                    .{ 0, v[1], 0, 0 },
                    .{ 0, 0, v[2], 0 },
                    .{ 0, 0, 0, 1 },
                },
            };
        }

        pub fn mul(self: *const Self, other: *const Self) Matrix(T, rows, cols) {
            var result: Matrix(T, rows, cols) = undefined;
            for (0..rows) |r| {
                for (0..cols) |c| {
                    result.data[r][c] = @reduce(.Add, self.row(r) * other.column(c));
                }
            }
            return result;
        }

        pub fn row(self: *const Self, row_idx: usize) @Vector(cols, T) {
            return self.data[row_idx];
        }

        pub fn column(self: *const Self, col_idx: usize) @Vector(rows, T) {
            var result: @Vector(rows, T) = undefined;
            for (0..rows) |i| {
                result[i] = self.data[i][col_idx];
            }
            return result;
        }

        pub fn columns() usize {
            return cols;
        }

        pub fn ptr(self: *const Self) [*]const T {
            return @ptrCast(&self.data[0][0]);
        }
    };
}

pub const Mat4 = Matrix(f32, 4, 4);
