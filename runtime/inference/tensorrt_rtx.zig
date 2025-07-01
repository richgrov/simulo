const std = @import("std");
const util = @import("util");

const ffi = @cImport({
    @cInclude("tensorrt_rtx_ffi.h");
});

pub const Keypoint = struct {
    pos: @Vector(2, f32),
    score: f32,
};

pub const Box = struct {
    pos: @Vector(2, f32),
    size: @Vector(2, f32),
};

pub const Detection = struct {
    box: Box,
    score: f32,
    keypoints: [17]Keypoint,
};

pub const Inference = struct {
    ctx: ?*anyopaque,
    input_buffers: [2][*]f32,

    pub fn init() !Inference {
        var path_buf: [512]u8 = undefined;
        const model_path = try util.getResourcePath("rtmo-m.onnx", &path_buf);
        const ctx = ffi.trt_rtx_create(model_path);
        if (ctx == null) return error.TensorRTError;
        return .{
            .ctx = ctx,
            .input_buffers = .{
                ffi.trt_rtx_input_buffer(ctx, 0),
                ffi.trt_rtx_input_buffer(ctx, 1),
            },
        };
    }

    pub fn deinit(self: *Inference) void {
        ffi.trt_rtx_destroy(self.ctx);
    }

    pub fn run(self: *Inference, input_idx: usize, outDets: []Detection) !usize {
        const n = ffi.trt_rtx_run(self.ctx, @intCast(c_int, input_idx),
            @ptrCast([*c]ffi.RtxDetection, outDets.ptr), outDets.len);
        return @intCast(usize, n);
    }
};
