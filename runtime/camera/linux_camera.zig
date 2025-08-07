const std = @import("std");
const linux = std.os.linux;
const v42l = @cImport({
    @cInclude("linux/videodev2.h");
});

const OutMode = union(enum) {
    bytes: [2][*]u8,
    floats: [2][*]f32,
};

pub const LinuxCamera = struct {
    fd: i32,
    buffer: [*]u8,
    buffer_len: usize,

    out: OutMode,
    out_idx: usize,

    pub fn init(out_bufs: [2][*]u8) !LinuxCamera {
        const fd: i32 = @intCast(linux.open("/dev/video0", .{ .ACCMODE = .RDWR, .NONBLOCK = true }, 0));
        if (fd < 0) {
            return error.OpenFailed;
        }

        var caps = v42l.v4l2_capability{};
        if (linux.ioctl(fd, v42l.VIDIOC_QUERYCAP, @intFromPtr(&caps)) < 0) {
            return error.CapFailed;
        }

        var fmt = v42l.v4l2_format{
            .type = v42l.V4L2_BUF_TYPE_VIDEO_CAPTURE,
            .fmt = .{ .pix = .{
                .width = 640,
                .height = 480,
                .pixelformat = v42l.V4L2_PIX_FMT_YUYV,
                .field = v42l.V4L2_FIELD_ANY,
            } },
        };
        if (linux.ioctl(fd, v42l.VIDIOC_S_FMT, @intFromPtr(&fmt)) < 0) {
            return error.SetFormatFailed;
        }

        var req = v42l.v4l2_requestbuffers{
            .count = 1,
            .type = v42l.V4L2_BUF_TYPE_VIDEO_CAPTURE,
            .memory = v42l.V4L2_MEMORY_MMAP,
        };
        if (linux.ioctl(fd, v42l.VIDIOC_REQBUFS, @intFromPtr(&req)) < 0 or req.count < 1) {
            return error.ReqBufsFailed;
        }

        var buf = v42l.v4l2_buffer{
            .type = v42l.V4L2_BUF_TYPE_VIDEO_CAPTURE,
            .memory = v42l.V4L2_MEMORY_MMAP,
            .index = 0,
        };
        if (linux.ioctl(fd, v42l.VIDIOC_QUERYBUF, @intFromPtr(&buf)) < 0) {
            return error.QueryBufFailed;
        }

        const mmap_ptr = linux.mmap(
            null,
            buf.length,
            linux.PROT.READ | linux.PROT.WRITE,
            .{ .TYPE = .SHARED },
            fd,
            @intCast(buf.m.offset),
        );
        if (mmap_ptr == std.math.maxInt(usize)) {
            return error.MMapFailed;
        }

        if (linux.ioctl(fd, v42l.VIDIOC_QBUF, @intFromPtr(&buf)) < 0) {
            return error.QBufFailed;
        }

        var ty = v42l.V4L2_BUF_TYPE_VIDEO_CAPTURE;
        if (linux.ioctl(fd, v42l.VIDIOC_STREAMON, @intFromPtr(&ty)) < 0) {
            return error.StreamOnFailed;
        }

        return LinuxCamera{
            .fd = fd,
            .buffer = @ptrFromInt(mmap_ptr),
            .buffer_len = buf.length,

            .out = .{ .bytes = out_bufs },
            .out_idx = 0,
        };
    }

    pub fn deinit(self: *LinuxCamera) void {
        var ty = v42l.V4L2_BUF_TYPE_VIDEO_CAPTURE;
        _ = linux.ioctl(self.fd, v42l.VIDIOC_STREAMOFF, @intFromPtr(&ty));
        _ = linux.close(self.fd);
    }

    pub fn setFloatMode(self: *LinuxCamera, out: [2][*]f32) void {
        self.out = .{ .floats = out };
    }

    pub fn swapBuffers(self: *LinuxCamera) !usize {
        var pollfd = linux.pollfd{ .fd = self.fd, .events = linux.POLL.IN, .revents = 0 };
        if (linux.poll(@ptrCast(&pollfd), 1, -1) <= 0) {
            return error.SelectFailed;
        }

        var buf = v42l.v4l2_buffer{
            .type = v42l.V4L2_BUF_TYPE_VIDEO_CAPTURE,
            .memory = v42l.V4L2_MEMORY_MMAP,
        };
        if (linux.ioctl(self.fd, v42l.VIDIOC_DQBUF, @intFromPtr(&buf)) < 0) {
            return error.DQBufFailed;
        }

        if (buf.bytesused != 480 * 640 * 2) {
            return error.InvalidFrameSize;
        }

        const frame = self.buffer[0..buf.bytesused];
        const out_idx = self.out_idx;
        self.out_idx = (self.out_idx + 1) % 2;

        const width = 640;
        const height = 480;

        switch (self.out) {
            .bytes => |out_bufs| {
                const out_buf = out_bufs[out_idx];
                yuyvToRgbu8(frame, out_buf, width, height);
            },
            .floats => |out_bufs| {
                const out_buf = out_bufs[out_idx];
                yuyvToRgbf32(frame, out_buf, width, height);
            },
        }

        _ = linux.ioctl(self.fd, v42l.VIDIOC_QBUF, @intFromPtr(&buf)); // Re-queue buffer

        return out_idx;
    }
};

fn yuyvToRgbu8(yuyv_data: []const u8, rgb_data: [*]u8, width: u32, height: u32) void {
    for (0..height) |i| {
        var j: u32 = 0;
        while (j < width) : (j += 2) {
            const yuyv_idx = (i * width + j) * 2;
            const y0 = @as(i32, yuyv_data[yuyv_idx]);
            const u = @as(i32, yuyv_data[yuyv_idx + 1]);
            const y1 = @as(i32, yuyv_data[yuyv_idx + 2]);
            const v = @as(i32, yuyv_data[yuyv_idx + 3]);

            const c = y0 - 16;
            const d = u - 128;
            const e = v - 128;

            const r0 = @max(0, @min(255, (298 * c + 409 * e + 128) >> 8));
            const g0 = @max(0, @min(255, (298 * c - 100 * d - 208 * e + 128) >> 8));
            const b0 = @max(0, @min(255, (298 * c + 516 * d + 128) >> 8));

            const rgb_idx0 = (i * width + j) * 3;
            rgb_data[rgb_idx0] = @intCast(r0);
            rgb_data[rgb_idx0 + 1] = @intCast(g0);
            rgb_data[rgb_idx0 + 2] = @intCast(b0);

            if (j + 1 < width) {
                const c1 = y1 - 16;
                const r1 = @max(0, @min(255, (298 * c1 + 409 * e + 128) >> 8));
                const g1 = @max(0, @min(255, (298 * c1 - 100 * d - 208 * e + 128) >> 8));
                const b1 = @max(0, @min(255, (298 * c1 + 516 * d + 128) >> 8));

                const rgb_idx1 = (i * width + j + 1) * 3;
                rgb_data[rgb_idx1] = @intCast(r1);
                rgb_data[rgb_idx1 + 1] = @intCast(g1);
                rgb_data[rgb_idx1 + 2] = @intCast(b1);
            }
        }
    }
}

fn yuyvToRgbf32(yuyv_data: []const u8, rgb_data: [*]f32, width: u32, height: u32) void {
    for (0..height) |i| {
        var j: u32 = 0;
        while (j < width) : (j += 2) {
            const yuyv_idx = (i * width + j) * 2;
            const y0 = @as(i32, yuyv_data[yuyv_idx]);
            const u = @as(i32, yuyv_data[yuyv_idx + 1]);
            const y1 = @as(i32, yuyv_data[yuyv_idx + 2]);
            const v = @as(i32, yuyv_data[yuyv_idx + 3]);

            const c = y0 - 16;
            const d = u - 128;
            const e = v - 128;

            const r0_int = @max(0, @min(255, (298 * c + 409 * e + 128) >> 8));
            const g0_int = @max(0, @min(255, (298 * c - 100 * d - 208 * e + 128) >> 8));
            const b0_int = @max(0, @min(255, (298 * c + 516 * d + 128) >> 8));

            const r0 = @as(f32, @floatFromInt(r0_int)) / 255.0;
            const g0 = @as(f32, @floatFromInt(g0_int)) / 255.0;
            const b0 = @as(f32, @floatFromInt(b0_int)) / 255.0;

            const ch_stride = 640 * 640;
            const adjusted_y0 = (640 - 480) / 2 + i;
            rgb_data[ch_stride * 0 + adjusted_y0 * width + j] = r0;
            rgb_data[ch_stride * 1 + adjusted_y0 * width + j] = g0;
            rgb_data[ch_stride * 2 + adjusted_y0 * width + j] = b0;

            if (j + 1 < width) {
                const c1 = y1 - 16;
                const r1_int = @max(0, @min(255, (298 * c1 + 409 * e + 128) >> 8));
                const g1_int = @max(0, @min(255, (298 * c1 - 100 * d - 208 * e + 128) >> 8));
                const b1_int = @max(0, @min(255, (298 * c1 + 516 * d + 128) >> 8));

                const r1 = @as(f32, @floatFromInt(r1_int)) / 255.0;
                const g1 = @as(f32, @floatFromInt(g1_int)) / 255.0;
                const b1 = @as(f32, @floatFromInt(b1_int)) / 255.0;

                const adjusted_y1 = (640 - 480) / 2 + i;
                rgb_data[ch_stride * 0 + adjusted_y1 * width + j + 1] = r1;
                rgb_data[ch_stride * 1 + adjusted_y1 * width + j + 1] = g1;
                rgb_data[ch_stride * 2 + adjusted_y1 * width + j + 1] = b1;
            }
        }
    }
}

test "YUYV to RGB bytes exact conversion" {
    const testing = std.testing;

    const yuyv_data = [_]u8{
        100, 150, 200, 100,
    };

    var rgb_data: [6]u8 = undefined;

    try yuyvToRgbu8(&yuyv_data, &rgb_data, 2, 1);

    try testing.expectEqual(@as(u8, 53), rgb_data[0]);
    try testing.expectEqual(@as(u8, 112), rgb_data[1]);
    try testing.expectEqual(@as(u8, 142), rgb_data[2]);
    try testing.expectEqual(@as(u8, 169), rgb_data[3]);
    try testing.expectEqual(@as(u8, 228), rgb_data[4]);
    try testing.expectEqual(@as(u8, 255), rgb_data[5]);
}

test "YUYV to RGB floats exact conversion" {
    const testing = std.testing;

    const yuyv_data = [_]u8{
        100, 150, 200, 100,
    };

    var rgb_data: [6]f32 = undefined;

    try yuyvToRgbf32(&yuyv_data, &rgb_data, 2, 1);

    try testing.expectApproxEqAbs(@as(f32, 53.0 / 255.0), rgb_data[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 169.0 / 255.0), rgb_data[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 112.0 / 255.0), rgb_data[2], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 228.0 / 255.0), rgb_data[3], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 142.0 / 255.0), rgb_data[4], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 255.0 / 255.0), rgb_data[5], 0.001);
}

test "YUYV conversion error on invalid data size" {
    const testing = std.testing;

    const yuyv_data = [_]u8{ 76, 84, 255 };
    var rgb_data: [12]u8 = undefined;

    try testing.expectError(error.InvalidYUYVDataSize, yuyvToRgbu8(&yuyv_data, &rgb_data, 2, 1));

    var rgb_floats: [6]f32 = undefined;
    try testing.expectError(error.InvalidYUYVDataSize, yuyvToRgbf32(&yuyv_data, &rgb_floats, 2, 1));
}

test "YUYV black exact values" {
    const testing = std.testing;

    const yuyv_data = [_]u8{
        16, 128, 16, 128,
    };

    var rgb_data: [6]u8 = undefined;

    try yuyvToRgbu8(&yuyv_data, &rgb_data, 2, 1);

    try testing.expectEqual(@as(u8, 0), rgb_data[0]);
    try testing.expectEqual(@as(u8, 0), rgb_data[1]);
    try testing.expectEqual(@as(u8, 0), rgb_data[2]);
    try testing.expectEqual(@as(u8, 0), rgb_data[3]);
    try testing.expectEqual(@as(u8, 0), rgb_data[4]);
    try testing.expectEqual(@as(u8, 0), rgb_data[5]);
}

test "YUYV white exact values" {
    const testing = std.testing;

    const yuyv_data = [_]u8{
        235, 128, 235, 128,
    };

    var rgb_data: [6]u8 = undefined;

    try yuyvToRgbu8(&yuyv_data, &rgb_data, 2, 1);

    try testing.expectEqual(@as(u8, 255), rgb_data[0]);
    try testing.expectEqual(@as(u8, 255), rgb_data[1]);
    try testing.expectEqual(@as(u8, 255), rgb_data[2]);
    try testing.expectEqual(@as(u8, 255), rgb_data[3]);
    try testing.expectEqual(@as(u8, 255), rgb_data[4]);
    try testing.expectEqual(@as(u8, 255), rgb_data[5]);
}

test "YUYV chroma sharing verification" {
    const testing = std.testing;

    const yuyv_data = [_]u8{
        50, 200, 150, 50,
    };

    var rgb_data: [6]u8 = undefined;

    try yuyvToRgbu8(&yuyv_data, &rgb_data, 2, 1);

    try testing.expectEqual(@as(u8, 0), rgb_data[0]);
    try testing.expectEqual(@as(u8, 75), rgb_data[1]);
    try testing.expectEqual(@as(u8, 185), rgb_data[2]);
    try testing.expectEqual(@as(u8, 31), rgb_data[3]);
    try testing.expectEqual(@as(u8, 191), rgb_data[4]);
    try testing.expectEqual(@as(u8, 255), rgb_data[5]);
}
