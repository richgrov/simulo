const std = @import("std");

const vulkan = @import("util").vulkan;
const y_direction = if (vulkan) -1 else 1;

fn Matrix(T: type, comptime rows: usize, comptime cols: usize) type {
    return struct {
        const Self = @This();

        data: [cols]@Vector(rows, T),

        pub fn zero() Self {
            return std.mem.zeroInit(Self, .{});
        }

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
                    .{ 0, y_direction * 2.0 / height, 0, 0 },
                    .{ 0, 0, 1.0 / depth, 0 },
                    .{ -1, y_direction * -1, -near / depth, 1 },
                },
            };
        }

        pub fn perspective(aspect: f32, fov: f32, near: f32, far: f32) Matrix(f32, 4, 4) {
            const tan_fov = @tan(fov / 2);
            const depth = far / (far - near);
            // zig fmt: off
            return .{ .data = [_]@Vector(4, f32){
                .{ 1.0 / (aspect * tan_fov), 0,                     0,             0 },
                .{ 0,                        y_direction / tan_fov, 0,             0 },
                .{ 0,                        0,                     depth,         1 },
                .{ 0,                        0,                     -near * depth, 0 },
            } };
            // zig fmt: on
        }

        pub fn offAxisPerspective(top: f32, bottom: f32, left: f32, right: f32, near: f32, far: f32) Matrix(f32, 4, 4) {
            const depth = far / (far - near);
            // zig fmt: off
            return .{ .data = [_]@Vector(4, f32){
                .{ (2 * near) / (right - left),     0,                               0,             0 },
                .{ 0,                               (2 * near) / (top - bottom),     0,             0 },
                .{ (right + left) / (right - left), (top + bottom) / (top - bottom), depth,         1 },
                .{ 0,                               0,                               -near * depth, 0 },
            } };
            // zig fmt: on
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

        pub fn rotateZ(angle: f32) Matrix(f32, 4, 4) {
            return .{
                .data = [_]@Vector(4, f32){
                    .{ @cos(angle), @sin(angle), 0, 0 },
                    .{ -@sin(angle), @cos(angle), 0, 0 },
                    .{ 0, 0, 1, 0 },
                    .{ 0, 0, 0, 1 },
                },
            };
        }

        pub fn scale(v: @Vector(rows - 1, T)) Matrix(T, rows, rows) {
            if (rows != cols) {
                @compileError("matrix must be square to scale");
            }

            var data: [cols]@Vector(rows, T) = undefined;
            inline for (0..cols) |i| {
                var vec: @Vector(rows, T) = @splat(0.0);
                if (i == cols - 1) {
                    vec[rows - 1] = 1.0;
                } else {
                    vec[i] = v[i];
                }
                data[i] = vec;
            }

            return .{ .data = data };
        }

        pub fn fromRowMajorPtr(p: [*]const T) Self {
            var result: Self = undefined;
            for (0..cols) |c| {
                for (0..rows) |r| {
                    result.data[c][r] = p[r * cols + c];
                }
            }
            return result;
        }

        pub fn fromColumnMajorPtr(p: [*]const T) Self {
            var result: Self = undefined;
            for (0..rows) |r| {
                for (0..cols) |c| {
                    result.data[c][r] = p[c * rows + r];
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
                result[c] = self.data[c][row_idx];
            }
            return result;
        }

        pub fn columns() usize {
            return cols;
        }

        pub fn ptr(self: *const Self) [*]const T {
            return @ptrCast(&self.data[0][0]);
        }

        pub fn format(self: *const Self, writer: anytype) !void {
            try writer.print("Matrix({any})", .{self.data});
        }
    };
}

pub const DMat3 = Matrix(f64, 3, 3);
pub const Mat4 = Matrix(f32, 4, 4);

fn expectIdentity(comptime N: usize) !void {
    const Mat = Matrix(f32, N, N);
    const m = Mat.identity();
    inline for (0..N) |r| {
        inline for (0..N) |c| {
            try std.testing.expectEqual(
                @as(f32, if (r == c) 1 else 0),
                m.data[c][r],
            );
        }
    }
}

test "identity matrices 2x2 through 5x5" {
    try expectIdentity(2);
    try expectIdentity(3);
    try expectIdentity(4);
    try expectIdentity(5);
}

test "fromRowMajorPtr rectangular" {
    const Mat23 = Matrix(i32, 2, 3);
    var arr23 = [_]i32{ 1, 2, 3, 4, 5, 6 };
    const m23 = Mat23.fromRowMajorPtr(&arr23);
    std.debug.print("{any}\n", .{m23});
    try std.testing.expectEqual(@as(i32, 1), m23.row(0)[0]);
    try std.testing.expectEqual(@as(i32, 2), m23.row(0)[1]);
    try std.testing.expectEqual(@as(i32, 3), m23.row(0)[2]);
    try std.testing.expectEqual(@as(i32, 4), m23.row(1)[0]);
    try std.testing.expectEqual(@as(i32, 5), m23.row(1)[1]);
    try std.testing.expectEqual(@as(i32, 6), m23.row(1)[2]);

    const Mat32 = Matrix(i32, 3, 2);
    var arr32 = [_]i32{ 1, 2, 3, 4, 5, 6 };
    const m32 = Mat32.fromRowMajorPtr(&arr32);
    try std.testing.expectEqual(@as(i32, 1), m32.column(0)[0]);
    try std.testing.expectEqual(@as(i32, 3), m32.column(0)[1]);
    try std.testing.expectEqual(@as(i32, 5), m32.column(0)[2]);
    try std.testing.expectEqual(@as(i32, 2), m32.column(1)[0]);
    try std.testing.expectEqual(@as(i32, 4), m32.column(1)[1]);
    try std.testing.expectEqual(@as(i32, 6), m32.column(1)[2]);
}

test "matrix multiply and vector multiply" {
    const Mat2 = Matrix(f32, 2, 2);
    var a_data = [_]f32{ 1, 2, 3, 4 };
    var b_data = [_]f32{ 5, 6, 7, 8 };
    const a = Mat2.fromRowMajorPtr(&a_data);
    const b = Mat2.fromRowMajorPtr(&b_data);
    const prod = a.matmul(&b);
    try std.testing.expectEqual(@as(f32, 19), prod.row(0)[0]);
    try std.testing.expectEqual(@as(f32, 22), prod.row(0)[1]);
    try std.testing.expectEqual(@as(f32, 43), prod.row(1)[0]);
    try std.testing.expectEqual(@as(f32, 50), prod.row(1)[1]);

    const vec = @Vector(2, f32){ 1, 2 };
    const vec_res = a.vecmul(vec);
    try std.testing.expectEqual(@as(f32, 5), vec_res[0]);
    try std.testing.expectEqual(@as(f32, 11), vec_res[1]);
}

test "scale 2x2" {
    const Mat2 = Matrix(f32, 2, 2);
    const s = @Vector(1, f32){3.0};
    const scale_mat = Mat2.scale(s);
    try std.testing.expectEqual(@as(f32, 3.0), scale_mat.data[0][0]);
    try std.testing.expectEqual(@as(f32, 0.0), scale_mat.data[0][1]);
    try std.testing.expectEqual(@as(f32, 0.0), scale_mat.data[1][0]);
    try std.testing.expectEqual(@as(f32, 1.0), scale_mat.data[1][1]);
}

test "scale 3x3" {
    const Mat3 = Matrix(f64, 3, 3);
    const v = @Vector(2, f64){ 2.0, 4.0 };
    const scale_mat = Mat3.scale(v);
    try std.testing.expectEqual(@as(f64, 2.0), scale_mat.data[0][0]);
    try std.testing.expectEqual(@as(f64, 0.0), scale_mat.data[0][1]);
    try std.testing.expectEqual(@as(f64, 0.0), scale_mat.data[0][2]);
    try std.testing.expectEqual(@as(f64, 0.0), scale_mat.data[1][0]);
    try std.testing.expectEqual(@as(f64, 4.0), scale_mat.data[1][1]);
    try std.testing.expectEqual(@as(f64, 0.0), scale_mat.data[1][2]);
    try std.testing.expectEqual(@as(f64, 0.0), scale_mat.data[2][0]);
    try std.testing.expectEqual(@as(f64, 0.0), scale_mat.data[2][1]);
    try std.testing.expectEqual(@as(f64, 1.0), scale_mat.data[2][2]);
}

test "scale 4x4 with different values" {
    const v = @Vector(3, f32){ 1.0, 2.0, 3.0 };
    const scale_mat = Mat4.scale(v);
    try std.testing.expectEqual(@as(f32, 1.0), scale_mat.data[0][0]);
    try std.testing.expectEqual(@as(f32, 0.0), scale_mat.data[0][1]);
    try std.testing.expectEqual(@as(f32, 0.0), scale_mat.data[0][2]);
    try std.testing.expectEqual(@as(f32, 0.0), scale_mat.data[0][3]);
    try std.testing.expectEqual(@as(f32, 0.0), scale_mat.data[1][0]);
    try std.testing.expectEqual(@as(f32, 2.0), scale_mat.data[1][1]);
    try std.testing.expectEqual(@as(f32, 0.0), scale_mat.data[1][2]);
    try std.testing.expectEqual(@as(f32, 0.0), scale_mat.data[1][3]);
    try std.testing.expectEqual(@as(f32, 0.0), scale_mat.data[2][0]);
    try std.testing.expectEqual(@as(f32, 0.0), scale_mat.data[2][1]);
    try std.testing.expectEqual(@as(f32, 3.0), scale_mat.data[2][2]);
    try std.testing.expectEqual(@as(f32, 0.0), scale_mat.data[2][3]);
    try std.testing.expectEqual(@as(f32, 0.0), scale_mat.data[3][0]);
    try std.testing.expectEqual(@as(f32, 0.0), scale_mat.data[3][1]);
    try std.testing.expectEqual(@as(f32, 0.0), scale_mat.data[3][2]);
    try std.testing.expectEqual(@as(f32, 1.0), scale_mat.data[3][3]);
}
