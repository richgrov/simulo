const std = @import("std");
const builtin = @import("builtin");

pub const Camera = @import("camera/camera.zig").Camera;
pub const Gpu = @import("gpu/gpu.zig").Gpu;
pub const Renderer = @import("render/renderer.zig").Renderer;
pub const Window = @import("window/window.zig").Window;

const ort = @import("perception/onnxruntime.zig");

const rtmo = @embedFile("perception/rtmo-m.onnx");
const vulkan = builtin.target.os.tag == .windows or builtin.target.os.tag == .linux;
const text_vert = if (vulkan) @embedFile("shader/text.vert") else &[_]u8{0};
const text_frag = if (vulkan) @embedFile("shader/text.frag") else &[_]u8{0};
const model_vert = if (vulkan) @embedFile("shader/model.vert") else &[_]u8{0};
const model_frag = if (vulkan) @embedFile("shader/model.frag") else &[_]u8{0};
const arial = @embedFile("res/arial.ttf");

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

pub const Perception = struct {
    ort_api: *const ort.OrtApi,
    ort_env: *ort.OrtEnv,
    ort_options: *ort.OrtSessionOptions,
    ort_session: *ort.OrtSession,
    ort_allocator: *ort.OrtAllocator,
    input_tensor: *ort.OrtValue,

    pub fn init() !Perception {
        const ort_api: *const ort.OrtApi = ort.OrtGetApiBase().*.GetApi.?(ort.ORT_API_VERSION);

        var ort_env: ?*ort.OrtEnv = null;
        try errIfStatus(ort_api.CreateEnv.?(ort.ORT_LOGGING_LEVEL_WARNING, "ONNX", &ort_env), ort_api);
        errdefer ort_api.ReleaseEnv.?(ort_env);

        var ort_options: ?*ort.OrtSessionOptions = null;
        try errIfStatus(ort_api.CreateSessionOptions.?(&ort_options), ort_api);
        errdefer ort_api.ReleaseSessionOptions.?(ort_options);

        if (builtin.os.tag == .macos) {
            const coreml: [:0]const u8 = "CoreML";
            try errIfStatus(
                ort_api.*.SessionOptionsAppendExecutionProvider.?(ort_options, coreml, null, null, 0),
                ort_api,
            );
        }

        var ort_session: ?*ort.OrtSession = null;
        try errIfStatus(
            ort_api.CreateSessionFromArray.?(ort_env, &rtmo[0], rtmo.len, ort_options, &ort_session),
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

        const input_tensor = try createTensor(ort_api, ort_allocator.?, &[_]i64{ 1, 3, 640, 640 });
        errdefer ort_api.ReleaseValue.?(input_tensor);

        return Perception{
            .ort_api = ort_api,
            .ort_env = ort_env.?,
            .ort_options = ort_options.?,
            .ort_session = ort_session.?,
            .ort_allocator = ort_allocator.?,
            .input_tensor = input_tensor,
        };
    }

    pub fn deinit(self: *Perception) void {
        self.ort_api.ReleaseValue.?(self.input_tensor);
        self.ort_api.ReleaseAllocator.?(self.ort_allocator);
        self.ort_api.ReleaseSession.?(self.ort_session);
        self.ort_api.ReleaseSessionOptions.?(self.ort_options);
        self.ort_api.ReleaseEnv.?(self.ort_env);
    }

    pub fn run(self: *Perception, img_data: []const f32) !void {
        var input_data: ?[*]f32 = null;
        try errIfStatus(self.ort_api.GetTensorMutableData.?(self.input_tensor, @ptrCast(&input_data)), self.ort_api);
        @memcpy(input_data.?, img_data);

        var output_slice = [_]?*ort.OrtValue{ null, null };
        try errIfStatus(self.ort_api.Run.?(
            self.ort_session,
            null,
            &[_][*:0]const u8{"input"},
            &[_]*ort.OrtValue{self.input_tensor},
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
        var detections_data: ?[*]f32 = null;
        try errIfStatus(self.ort_api.GetTensorMutableData.?(detections, @ptrCast(&detections_data)), self.ort_api);

        for (0..@intCast(n_detections)) |i| {
            const x = detections_data.?[i * 5];
            const y = detections_data.?[i * 5 + 1];
            const w = detections_data.?[i * 5 + 2];
            const h = detections_data.?[i * 5 + 3];
            const score = detections_data.?[i * 5 + 4];

            std.debug.print("Detection {d}: {d:.2} {d:.2} {d:.2} {d:.2} {d:.2}\n", .{ i, x, y, w, h, score });
        }
    }

    fn get_tensor_shape(self: *Perception, tensor: *ort.OrtValue) !std.ArrayList(i64) {
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

pub export fn text_vertex_bytes() *const u8 {
    return &text_vert[0];
}

pub export fn text_vertex_len() usize {
    return text_vert.len;
}

pub export fn text_fragment_bytes() *const u8 {
    return &text_frag[0];
}

pub export fn text_fragment_len() usize {
    return text_frag.len;
}

pub export fn model_vertex_bytes() *const u8 {
    return &model_vert[0];
}

pub export fn model_vertex_len() usize {
    return model_vert.len;
}

pub export fn model_fragment_bytes() *const u8 {
    return &model_frag[0];
}

pub export fn model_fragment_len() usize {
    return model_frag.len;
}

pub export fn arial_bytes() *const u8 {
    return &arial[0];
}

pub export fn arial_len() usize {
    return arial.len;
}
