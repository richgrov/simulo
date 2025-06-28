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
        if (linux.ioctl(fd, v42l.VIDIOC_QUERYCAP, &caps) < 0) {
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
        if (linux.ioctl(fd, v42l.VIDIOC_S_FMT, &fmt) < 0) {
            return error.SetFormatFailed;
        }

        var req = v42l.v4l2_requestbuffers{
            .count = 1,
            .type = v42l.V4L2_BUF_TYPE_VIDEO_CAPTURE,
            .memory = v42l.V4L2_MEMORY_MMAP,
        };
        if (linux.ioctl(fd, v42l.VIDIOC_REQBUFS, &req) < 0 or req.count < 1) {
            return error.ReqBufsFailed;
        }

        var buf = v42l.v4l2_buffer{
            .type = v42l.V4L2_BUF_TYPE_VIDEO_CAPTURE,
            .memory = v42l.V4L2_MEMORY_MMAP,
            .index = 0,
        };
        if (linux.ioctl(fd, v42l.VIDIOC_QUERYBUF, &buf) < 0) {
            return error.QueryBufFailed;
        }

        const mmap_ptr = linux.mmap(
            null,
            buf.length,
            linux.PROT_READ | linux.PROT_WRITE,
            linux.MAP_SHARED,
            fd,
            @intCast(buf.m.offset),
        );
        if (@intFromPtr(mmap_ptr) == @intFromPtr(linux.MAP_FAILED)) {
            return error.MMapFailed;
        }

        if (linux.ioctl(fd, v42l.VIDIOC_QBUF, &buf) < 0) {
            return error.QBufFailed;
        }

        var ty = v42l.V4L2_BUF_TYPE_VIDEO_CAPTURE;
        if (linux.ioctl(fd, v42l.VIDIOC_STREAMON, &ty) < 0) {
            return error.StreamOnFailed;
        }

        return LinuxCamera{
            .fd = fd,
            .buffer = @ptrCast(mmap_ptr),
            .buffer_len = buf.length,

            .out = out_bufs,
            .out_idx = 0,
        };
    }

    pub fn deinit(self: *LinuxCamera) void {
        var ty = v42l.V4L2_BUF_TYPE_VIDEO_CAPTURE;
        _ = linux.ioctl(self.fd, v42l.VIDIOC_STREAMOFF, &ty);
        _ = linux.close(self.fd);
    }

    pub fn setFloatMode(self: *LinuxCamera, out: [2][*]f32) void {
        self.out = out;
    }

    pub fn swapBuffers(self: *LinuxCamera) !usize {
        var pollfd = linux.pollfd{ .fd = self.fd, .events = linux.POLL.IN };
        if (linux.poll(&pollfd, 1, -1) <= 0) {
            return error.SelectFailed;
        }

        var buf = v42l.v4l2_buffer{
            .type = v42l.V4L2_BUF_TYPE_VIDEO_CAPTURE,
            .memory = v42l.V4L2_MEMORY_MMAP,
        };
        if (linux.ioctl(self.fd, v42l.VIDIOC_DQBUF, &buf) < 0) {
            return error.DQBufFailed;
        }

        if (buf.bytesused != 480 * 640 * 2) {
            return error.InvalidFrameSize;
        }

        //const frame = self.buffer[0..buf.bytesused];
        const out_idx = self.out_idx;
        self.out_idx = (self.out_idx + 1) % 2;

        switch (self.out) {
            .bytes => {},
            .floats => {},
        }

        _ = linux.ioctl(self.fd, v42l.VIDIOC_QBUF, &buf); // Re-queue buffer

        return out_idx;
    }
};
