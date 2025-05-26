const std = @import("std");
const builtin = @import("builtin");

pub const Camera = @import("camera/camera.zig").Camera;

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
