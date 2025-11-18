const builtin = @import("builtin");
const std = @import("std");
const util = @import("util");
const Logger = @import("../log.zig").Logger;

const ort = @import("onnxruntime.zig");
const ffi = @cImport({
    @cInclude("ffi.h");
});

const fs_storage = @import("../fs_storage.zig");

const detection_threshold = 0.5;

fn createTensor(ort_api: [*c]const ort.OrtApi, ort_allocator: *ort.OrtAllocator, comptime shape: []const i64, logger: anytype) !*ort.OrtValue {
    var tensor: ?*ort.OrtValue = null;
    if (ort_api.*.CreateTensorAsOrtValue.?(
        ort_allocator,
        &shape[0],
        shape.len,
        ort.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
        &tensor,
    )) |status| {
        logOnnxError(status, ort_api, logger);
        return error.OnnxError;
    }
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

fn logOnnxError(status: ort.OrtStatusPtr, ort_api: [*c]const ort.OrtApi, logger: anytype) void {
    const message = ort_api.*.GetErrorMessage.?(status);
    logger.err("Onnx error: {s}", .{message});
    ort_api.*.ReleaseStatus.?(status);
}

pub const Inference = struct {
    ort_api: *const ort.OrtApi,
    ort_env: *ort.OrtEnv,
    ort_options: *ort.OrtSessionOptions,
    ort_session: *ort.OrtSession,
    ort_rt_options: ?*ort.OrtTensorRTProviderOptionsV2,
    ort_allocator: *ort.OrtAllocator,
    input_tensors: [2]*ort.OrtValue,
    input_buffers: [2][*]f32,
    logger: Logger("inference", 2048),

    pub fn init() !Inference {
        const ort_api: *const ort.OrtApi = ort.OrtGetApiBase().*.GetApi.?(ort.ORT_API_VERSION);
        var logger = Logger("inference", 2048).init();

        var ort_env: ?*ort.OrtEnv = null;
        if (ort_api.CreateEnv.?(ort.ORT_LOGGING_LEVEL_WARNING, "ONNX", &ort_env)) |status| {
            logOnnxError(status, ort_api, &logger);
            return error.OnnxError;
        }
        errdefer ort_api.ReleaseEnv.?(ort_env);

        var ort_options: ?*ort.OrtSessionOptions = null;
        if (ort_api.CreateSessionOptions.?(&ort_options)) |status| {
            logOnnxError(status, ort_api, &logger);
            return error.OnnxError;
        }
        errdefer ort_api.ReleaseSessionOptions.?(ort_options);

        var ort_rt_options: ?*ort.OrtTensorRTProviderOptionsV2 = null;
        switch (comptime builtin.os.tag) {
            .linux => {
                if (ort_api.CreateTensorRTProviderOptions.?(&ort_rt_options)) |status| {
                    logOnnxError(status, ort_api, &logger);
                    return error.OnnxError;
                }
                errdefer ort_api.ReleaseTensorRTProviderOptions.?(ort_rt_options);

                const option_keys = [_][*:0]const u8{
                    "trt_engine_cache_enable",
                    "trt_engine_cache_path",
                    "trt_timing_cache_enable",
                    "trt_timing_cache_path",
                };

                var cache_dir_buf: [128]u8 = undefined;
                const cache_dir = fs_storage.getFilePath(&cache_dir_buf, "trt_cache") catch unreachable;

                const option_values = [_][*:0]const u8{
                    "1",
                    @ptrCast(cache_dir),
                    "1",
                    @ptrCast(cache_dir),
                };

                if (ort_api.UpdateTensorRTProviderOptions.?(
                    ort_rt_options,
                    @ptrCast(&option_keys),
                    @ptrCast(&option_values),
                    option_keys.len,
                )) |status| {
                    logOnnxError(status, ort_api, &logger);
                    return error.OnnxError;
                }
                if (ort_api.SessionOptionsAppendExecutionProvider_TensorRT_V2.?(ort_options, ort_rt_options)) |status| {
                    logOnnxError(status, ort_api, &logger);
                    return error.OnnxError;
                }
            },
            else => {},
        }

        var model_path_buf: [512]u8 = undefined;
        const model_path = try util.getResourcePath("rtmo-m.onnx", &model_path_buf);
        var ort_session: ?*ort.OrtSession = null;
        if (ort_api.CreateSession.?(ort_env, @ptrCast(model_path), ort_options, &ort_session)) |status| {
            logOnnxError(status, ort_api, &logger);
            return error.OnnxError;
        }
        errdefer ort_api.ReleaseSession.?(ort_session);

        var ort_memory_info: ?*ort.OrtMemoryInfo = null;
        if (ort_api.CreateCpuMemoryInfo.?(ort.OrtDeviceAllocator, ort.OrtMemTypeCPU, &ort_memory_info)) |status| {
            logOnnxError(status, ort_api, &logger);
            return error.OnnxError;
        }
        defer ort_api.ReleaseMemoryInfo.?(ort_memory_info);

        var ort_allocator: ?*ort.OrtAllocator = null;
        if (ort_api.CreateAllocator.?(ort_session, ort_memory_info.?, &ort_allocator)) |status| {
            logOnnxError(status, ort_api, &logger);
            return error.OnnxError;
        }
        errdefer ort_api.ReleaseAllocator.?(ort_allocator);

        var input_tensors: [2]*ort.OrtValue = undefined;
        var input_buffers: [2][*]f32 = undefined;
        for (0..2) |i| {
            const input_tensor = try createTensor(ort_api, ort_allocator.?, &[_]i64{ 1, 3, 640, 640 }, &logger);
            errdefer ort_api.ReleaseValue.?(input_tensor);
            input_tensors[i] = input_tensor;

            var input_data: ?[*]f32 = null;
            if (ort_api.GetTensorMutableData.?(input_tensor, @ptrCast(&input_data))) |status| {
                logOnnxError(status, ort_api, &logger);
                return error.OnnxError;
            }
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
            .ort_rt_options = ort_rt_options,
            .ort_allocator = ort_allocator.?,
            .input_tensors = input_tensors,
            .input_buffers = input_buffers,
            .logger = logger,
        };
    }

    pub fn deinit(self: *Inference) void {
        for (self.input_tensors) |input_tensor| {
            self.ort_api.ReleaseValue.?(input_tensor);
        }
        self.ort_api.ReleaseAllocator.?(self.ort_allocator);
        self.ort_api.ReleaseSession.?(self.ort_session);
        self.ort_api.ReleaseSessionOptions.?(self.ort_options);
        if (self.ort_rt_options) |ort_rt_options| {
            self.ort_api.ReleaseTensorRTProviderOptions.?(ort_rt_options);
        }
        self.ort_api.ReleaseEnv.?(self.ort_env);
    }

    pub fn run(self: *Inference, input_idx: usize, outDets: []Detection) !usize {
        var output_slice = [_]?*ort.OrtValue{ null, null };
        if (self.ort_api.Run.?(
            self.ort_session,
            null,
            &[_][*:0]const u8{"input"},
            &[_]*ort.OrtValue{self.input_tensors[input_idx]},
            1,
            &[_][*:0]const u8{ "dets", "keypoints" },
            2,
            &output_slice,
        )) |status| {
            logOnnxError(status, self.ort_api, &self.logger);
            return error.OnnxError;
        }

        const detections = output_slice[0].?;
        const keypoints = output_slice[1].?;
        defer self.ort_api.ReleaseValue.?(detections);
        defer self.ort_api.ReleaseValue.?(keypoints);

        const detect_dim = try self.get_tensor_shape(detections);
        defer detect_dim.deinit();

        const n_detections = detect_dim.items[1];
        var detections_data: [*]f32 = undefined;
        if (self.ort_api.GetTensorMutableData.?(detections, @ptrCast(&detections_data))) |status| {
            logOnnxError(status, self.ort_api, &self.logger);
            return error.OnnxError;
        }

        var keypoints_data: [*]f32 = undefined;
        if (self.ort_api.GetTensorMutableData.?(keypoints, @ptrCast(&keypoints_data))) |status| {
            logOnnxError(status, self.ort_api, &self.logger);
            return error.OnnxError;
        }

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

    fn get_tensor_shape(self: *Inference, tensor: *ort.OrtValue) !std.array_list.Managed(i64) {
        var type_shape_info: ?*ort.OrtTensorTypeAndShapeInfo = null;
        if (self.ort_api.GetTensorTypeAndShape.?(tensor, &type_shape_info)) |status| {
            logOnnxError(status, self.ort_api, &self.logger);
            return error.OnnxError;
        }
        defer self.ort_api.ReleaseTensorTypeAndShapeInfo.?(type_shape_info);

        var n_dimensions: usize = 0;
        if (self.ort_api.GetDimensionsCount.?(type_shape_info, &n_dimensions)) |status| {
            logOnnxError(status, self.ort_api, &self.logger);
            return error.OnnxError;
        }

        var dimensions = std.array_list.Managed(i64).init(std.heap.page_allocator);
        try dimensions.resize(n_dimensions);
        if (self.ort_api.GetDimensions.?(type_shape_info, dimensions.items.ptr, n_dimensions)) |status| {
            logOnnxError(status, self.ort_api, &self.logger);
            return error.OnnxError;
        }

        return dimensions;
    }
};
