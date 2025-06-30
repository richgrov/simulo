const builtin = @import("builtin");
const std = @import("std");
const util = @import("util");

const ort = @import("onnxruntime.zig");
const ffi = @cImport({
    @cInclude("ffi.h");
});

const detection_threshold = 0.5;

fn errIfStatus(status: ort.OrtStatusPtr, ort_api: [*c]const ort.OrtApi) !void {
    if (status) |s| {
        const message = ort_api.*.GetErrorMessage.?(s);
        std.log.err("Onnx error: {s}", .{message});
        ort_api.*.ReleaseStatus.?(s);
        return error.OnnxError;
    }
}

fn createTensor(ort_api: [*c]const ort.OrtApi, ort_allocator: *ort.OrtAllocator, comptime shape: []const i64) !*ort.OrtValue {
    var tensor: ?*ort.OrtValue = null;
    try errIfStatus(
        ort_api.*.CreateTensorAsOrtValue.?(
            ort_allocator,
            &shape[0],
            shape.len,
            ort.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
            &tensor,
        ),
        ort_api,
    );
    return tensor.?;
}

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
    ort_api: *const ort.OrtApi,
    ort_env: *ort.OrtEnv,
    ort_options: *ort.OrtSessionOptions,
    ort_session: *ort.OrtSession,
    ort_allocator: *ort.OrtAllocator,
    input_tensors: [2]*ort.OrtValue,
    input_buffers: [2][*]f32,

    pub fn init() !Inference {
        const ort_api: *const ort.OrtApi = ort.OrtGetApiBase().*.GetApi.?(ort.ORT_API_VERSION);

        var ort_env: ?*ort.OrtEnv = null;
        try errIfStatus(ort_api.CreateEnv.?(ort.ORT_LOGGING_LEVEL_WARNING, "ONNX", &ort_env), ort_api);
        errdefer ort_api.ReleaseEnv.?(ort_env);

        var ort_options: ?*ort.OrtSessionOptions = null;
        try errIfStatus(ort_api.CreateSessionOptions.?(&ort_options), ort_api);
        errdefer ort_api.ReleaseSessionOptions.?(ort_options);

        const execution_provider: ?[:0]const u8 = switch (builtin.os.tag) {
            .macos => "CoreML",
            .linux => "TensorRT",
            else => null,
        };

        if (execution_provider) |ep| {
            try errIfStatus(
                ort_api.*.SessionOptionsAppendExecutionProvider.?(ort_options, ep, null, null, 0),
                ort_api,
            );
        }

        var model_path_buf: [512]u8 = undefined;
        const model_path = try util.getResourcePath("rtmo-m.onnx", &model_path_buf);
        var ort_session: ?*ort.OrtSession = null;
        try errIfStatus(
            ort_api.CreateSession.?(ort_env, @ptrCast(model_path), ort_options, &ort_session),
            ort_api,
        );
        errdefer ort_api.ReleaseSession.?(ort_session);

        var ort_memory_info: ?*ort.OrtMemoryInfo = null;
        try errIfStatus(
            ort_api.CreateCpuMemoryInfo.?(ort.OrtDeviceAllocator, ort.OrtMemTypeCPU, &ort_memory_info),
            ort_api,
        );
        defer ort_api.ReleaseMemoryInfo.?(ort_memory_info);

        var ort_allocator: ?*ort.OrtAllocator = null;
        try errIfStatus(ort_api.CreateAllocator.?(ort_session, ort_memory_info.?, &ort_allocator), ort_api);
        errdefer ort_api.ReleaseAllocator.?(ort_allocator);

        var input_tensors: [2]*ort.OrtValue = undefined;
        var input_buffers: [2][*]f32 = undefined;
        for (0..2) |i| {
            const input_tensor = try createTensor(ort_api, ort_allocator.?, &[_]i64{ 1, 3, 640, 640 });
            errdefer ort_api.ReleaseValue.?(input_tensor);
            input_tensors[i] = input_tensor;

            var input_data: ?[*]f32 = null;
            try errIfStatus(ort_api.GetTensorMutableData.?(input_tensor, @ptrCast(&input_data)), ort_api);
            input_buffers[i] = input_data.?;
            for (0..640 * 640 * 3) |j| {
                input_data.?[j] = 114;
            }
        }

        return Inference{
            .ort_api = ort_api,
            .ort_env = ort_env.?,
            .ort_options = ort_options.?,
            .ort_session = ort_session.?,
            .ort_allocator = ort_allocator.?,
            .input_tensors = input_tensors,
            .input_buffers = input_buffers,
        };
    }

    pub fn deinit(self: *Inference) void {
        for (self.input_tensors) |input_tensor| {
            self.ort_api.ReleaseValue.?(input_tensor);
        }
        self.ort_api.ReleaseAllocator.?(self.ort_allocator);
        self.ort_api.ReleaseSession.?(self.ort_session);
        self.ort_api.ReleaseSessionOptions.?(self.ort_options);
        self.ort_api.ReleaseEnv.?(self.ort_env);
    }

    pub fn run(self: *Inference, input_idx: usize, outDets: []Detection) !usize {
        var output_slice = [_]?*ort.OrtValue{ null, null };
        try errIfStatus(self.ort_api.Run.?(
            self.ort_session,
            null,
            &[_][*:0]const u8{"input"},
            &[_]*ort.OrtValue{self.input_tensors[input_idx]},
            1,
            &[_][*:0]const u8{ "dets", "keypoints" },
            2,
            &output_slice,
        ), self.ort_api);

        const detections = output_slice[0].?;
        const keypoints = output_slice[1].?;
        defer self.ort_api.ReleaseValue.?(detections);
        defer self.ort_api.ReleaseValue.?(keypoints);

        const detect_dim = try self.get_tensor_shape(detections);
        defer detect_dim.deinit();

        const n_detections = detect_dim.items[1];
        var detections_data: [*]f32 = undefined;
        try errIfStatus(self.ort_api.GetTensorMutableData.?(detections, @ptrCast(&detections_data)), self.ort_api);

        var keypoints_data: [*]f32 = undefined;
        try errIfStatus(self.ort_api.GetTensorMutableData.?(keypoints, @ptrCast(&keypoints_data)), self.ort_api);

        const n_detections_usize: usize = @intCast(n_detections);
        var out_idx: usize = 0;
        for (0..@min(n_detections_usize, outDets.len)) |i| {
            const x1 = detections_data[i * 5];
            const y1 = detections_data[i * 5 + 1];
            const x2 = detections_data[i * 5 + 2];
            const y2 = detections_data[i * 5 + 3];
            const score = detections_data[i * 5 + 4];

            if (score < detection_threshold) {
                continue;
            }

            const size = @Vector(2, f32){ x2 - x1, y2 - y1 };
            outDets[out_idx].box.pos = @Vector(2, f32){ x1, y1 };
            outDets[out_idx].box.size = size;
            outDets[out_idx].score = score;

            for (0..17) |kp| {
                const kp_x = keypoints_data[i * 17 * 3 + kp * 3];
                const kp_y = keypoints_data[i * 17 * 3 + kp * 3 + 1];
                const kp_score = keypoints_data[i * 17 * 3 + kp * 3 + 2];
                outDets[out_idx].keypoints[kp].pos = @Vector(2, f32){ kp_x, kp_y };
                outDets[out_idx].keypoints[kp].score = kp_score;
            }

            out_idx += 1;
        }

        return out_idx;
    }

    fn get_tensor_shape(self: *Inference, tensor: *ort.OrtValue) !std.ArrayList(i64) {
        var type_shape_info: ?*ort.OrtTensorTypeAndShapeInfo = null;
        try errIfStatus(self.ort_api.GetTensorTypeAndShape.?(tensor, &type_shape_info), self.ort_api);
        defer self.ort_api.ReleaseTensorTypeAndShapeInfo.?(type_shape_info);

        var n_dimensions: usize = 0;
        try errIfStatus(self.ort_api.GetDimensionsCount.?(type_shape_info, &n_dimensions), self.ort_api);

        var dimensions = std.ArrayList(i64).init(std.heap.page_allocator);
        try dimensions.resize(n_dimensions);
        try errIfStatus(self.ort_api.GetDimensions.?(type_shape_info, dimensions.items.ptr, n_dimensions), self.ort_api);

        return dimensions;
    }
};
