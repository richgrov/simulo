const std = @import("std");

const vulkan = @import("../util/platform.zig").vulkan;
const Y_AXIS = if (vulkan) -1 else 1;

fn Matrix(T: type, comptime rows: usize, comptime cols: usize) type {
    return struct {
        const Self = @This();

        data: [cols]@Vector(rows, T),

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

        pub fn translate(v: @Vector(rows - 1, f32)) Matrix(f32, rows, rows) {
            if (rows != cols) {
                @compileError("matrix must be square to translate");
            }

            return .{
                .data = [_]@Vector(rows, f32){
                    .{ 1, 0, 0, 0 },
                    .{ 0, 1, 0, 0 },
                    .{ 0, 0, 1, 0 },
                    .{ v[0], v[1], v[2], 1 },
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

        pub fn fromRowMajorPtr(p: [*]const T) Self {
            var result: Self = undefined;
            for (0..rows) |r| {
                for (0..cols) |c| {
                    result.data[c][r] = p[c * cols + r];
                }
            }
            return result;
        }

        pub fn matmul(self: *const Self, other: *const Self) Matrix(T, rows, cols) {
            var result: Matrix(T, rows, cols) = undefined;
            for (0..rows) |r| {
                for (0..cols) |c| {
                    result.data[c][r] = @reduce(.Add, self.row(r) * other.column(c));
                }
            }
            return result;
        }

        pub fn vecmul(self: *const Self, v: @Vector(rows, T)) @Vector(rows, T) {
            if (rows != cols) {
                @compileError("square matrix required for vector multiplication");
            }

            var result: @Vector(cols, T) = undefined;
            for (0..rows) |r| {
                result[r] = @reduce(.Add, self.row(r) * v);
            }
            return result;
        }

        pub fn column(self: *const Self, column_idx: usize) @Vector(rows, T) {
            return self.data[column_idx];
        }

        pub fn row(self: *const Self, row_idx: usize) @Vector(cols, T) {
            var result: @Vector(cols, T) = undefined;
            for (0..cols) |c| {
                result[c] = self.data[row_idx][c];
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

pub const DMat3 = Matrix(f64, 3, 3);
pub const Mat4 = Matrix(f32, 4, 4);
