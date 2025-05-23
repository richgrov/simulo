const builtin = @import("builtin");

const ort = @import("perception/onnxruntime.zig");

const rtmo = @embedFile("perception/rtmo-m.onnx");
const vulkan = builtin.target.os.tag == .windows or builtin.target.os.tag == .linux;
const text_vert = if (vulkan) @embedFile("shader/text.vert") else &[_]u8{0};
const text_frag = if (vulkan) @embedFile("shader/text.frag") else &[_]u8{0};
const model_vert = if (vulkan) @embedFile("shader/model.vert") else &[_]u8{0};
const model_frag = if (vulkan) @embedFile("shader/model.frag") else &[_]u8{0};
const arial = @embedFile("res/arial.ttf");

pub const Perception = struct {
    ort_api: [*c]const ort.OrtApi,
    ort_env: *ort.OrtEnv,
    ort_options: *ort.OrtSessionOptions,
    ort_session: *ort.OrtSession,

    pub fn init() !Perception {
        const ort_api = ort.OrtGetApiBase().*.GetApi.?(ort.ORT_API_VERSION);
        var ort_env: ?*ort.OrtEnv = null;
        var ort_options: ?*ort.OrtSessionOptions = null;
        var ort_session: ?*ort.OrtSession = null;

        if (ort_api.*.CreateEnv.?(ort.ORT_LOGGING_LEVEL_INFO, "ONNX", &ort_env)) |status| {
            ort_api.*.ReleaseStatus.?(status);
            return error.OnnxInitFailed;
        }
        errdefer ort_api.*.ReleaseEnv.?(ort_env);

        if (ort_api.*.CreateSessionOptions.?(&ort_options)) |status| {
            ort_api.*.ReleaseStatus.?(status);
            return error.OnnxInitFailed;
        }
        errdefer ort_api.*.ReleaseSessionOptions.?(ort_options);

        //ort_api.*.SessionOptionsAppendExecutionProvider(ort_options, ort.ORT_TENSORRT);

        if (ort_api.*.CreateSessionFromArray.?(ort_env, &rtmo[0], rtmo.len, ort_options, &ort_session)) |status| {
            ort_api.*.ReleaseStatus.?(status);
            return error.OnnxInitFailed;
        }
        errdefer ort_api.*.ReleaseSession.?(ort_session);

        return Perception{
            .ort_api = ort_api,
            .ort_env = ort_env.?,
            .ort_options = ort_options.?,
            .ort_session = ort_session.?,
        };
    }

    pub fn deinit(self: *Perception) void {
        self.ort_api.*.ReleaseEnv.?(self.ort_env);
        self.ort_api.*.ReleaseSessionOptions.?(self.ort_options);
        self.ort_api.*.ReleaseSession.?(self.ort_session);
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
