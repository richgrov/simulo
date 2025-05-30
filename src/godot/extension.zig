const engine = @import("engine");
const std = @import("std");

const godot = @import("godot.zig");
const gd = godot.gd;

const ffi = @cImport({
    @cInclude("ffi.h");
});

pub const Vec2 = @Vector(2, f32);

const chessboardWidth = 7;
const chessboardHeight = 4;

fn dot(v1: @Vector(3, f64), v2: @Vector(3, f64)) f64 {
    return @reduce(.Add, v1 * v2);
}

fn matmul(mat: *const ffi.FfiMat3, vec: @Vector(3, f64)) @Vector(3, f64) {
    return @Vector(3, f64){
        dot(@Vector(3, f64){ mat.data[0], mat.data[1], mat.data[2] }, vec),
        dot(@Vector(3, f64){ mat.data[3], mat.data[4], mat.data[5] }, vec),
        dot(@Vector(3, f64){ mat.data[6], mat.data[7], mat.data[8] }, vec),
    };
}

fn perspective_transform(x: f32, y: f32, transform: *const ffi.FfiMat3) @Vector(2, f32) {
    const real_y = (y - (640 - 480) / 2);
    const res = matmul(transform, @Vector(3, f64){ x, real_y, 1 });
    return @Vector(2, f32){ @floatCast(res[0] / res[2]), @floatCast(res[1] / res[2]) };
}

const Perception = struct {
    detections: [32]engine.Detection,
    num_dets: usize,
    thread: ?std.Thread,
    mutex: std.Thread.Mutex,
    should_stop: bool,
    calibrated: bool,

    pub fn num_detections(self: *Perception) i64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return @intCast(self.num_dets);
    }

    pub fn get_detection_score(self: *Perception, detection_index: i64, keypoint_index: i64) f64 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const det_idx: usize = @intCast(detection_index);
        const kp_idx: usize = @intCast(keypoint_index);

        if (det_idx >= self.num_dets or kp_idx >= self.detections[0].keypoints.len) {
            return 0.0;
        }

        return @floatCast(self.detections[det_idx].keypoints[kp_idx].score);
    }

    pub fn get_detection_keypoint(self: *Perception, detection_index: i64, keypoint_index: i64) Vec2 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const det_idx: usize = @intCast(detection_index);
        const kp_idx: usize = @intCast(keypoint_index);

        if (det_idx >= self.num_dets or kp_idx >= self.detections[0].keypoints.len) {
            return Vec2{ 0, 0 };
        }

        return self.detections[det_idx].keypoints[kp_idx].pos;
    }

    fn detection_thread(self: *Perception) !void {
        const calibration_frames = [2]*ffi.OpenCvMat{
            ffi.create_opencv_mat(480, 640).?,
            ffi.create_opencv_mat(480, 640).?,
        };

        defer ffi.destroy_opencv_mat(calibration_frames[0]);
        defer ffi.destroy_opencv_mat(calibration_frames[1]);

        var camera = try engine.Camera.init([2][*]u8{
            ffi.get_opencv_mat_data(calibration_frames[0]),
            ffi.get_opencv_mat_data(calibration_frames[1]),
        });
        defer camera.deinit();

        var inference = try engine.Inference.init();
        defer inference.deinit();

        self.mutex.lock();
        self.calibrated = false;
        self.mutex.unlock();
        var local_calibrated = false;

        var transform = ffi.FfiMat3{};

        while (true) {
            self.mutex.lock();
            const should_stop = self.should_stop;
            self.mutex.unlock();

            if (should_stop) {
                break;
            }

            const frame_idx = camera.swapBuffers();

            if (!local_calibrated) {
                if (ffi.find_chessboard(calibration_frames[frame_idx], chessboardWidth, chessboardHeight, &transform)) {
                    camera.setFloatMode([2][*]f32{
                        inference.input_buffers[0],
                        inference.input_buffers[1],
                    });

                    local_calibrated = true;
                    self.mutex.lock();
                    self.calibrated = true;
                    self.mutex.unlock();

                    std.log.info("Calibrated", .{});
                }
                continue;
            }

            var local_detections: [32]engine.Detection = undefined;

            const n_dets = try inference.run(frame_idx, &local_detections);

            var transformed_detections: [32]engine.Detection = undefined;
            for (0..n_dets) |i| {
                const det = &local_detections[i];

                transformed_detections[i].pos = perspective_transform(det.pos[0], det.pos[1], &transform);
                transformed_detections[i].size = perspective_transform(det.size[0], det.size[1], &transform);

                for (0..det.keypoints.len) |k| {
                    const kp = det.keypoints[k];
                    const kp_pos = perspective_transform(kp.pos[0], kp.pos[1], &transform);
                    transformed_detections[i].keypoints[k].pos = kp_pos;
                    transformed_detections[i].keypoints[k].score = @floatCast(kp.score);
                }
            }

            self.mutex.lock();
            self.num_dets = n_dets;
            for (0..n_dets) |i| {
                self.detections[i] = transformed_detections[i];
            }
            self.mutex.unlock();
        }
    }

    pub fn start(self: *Perception) void {
        self.mutex = std.Thread.Mutex{};
        self.thread = null;
        self.should_stop = false;
        self.num_dets = 0;
        self.calibrated = false;

        if (std.Thread.spawn(.{}, detection_thread, .{self})) |thread| {
            self.mutex.lock();
            self.thread = thread;
            self.mutex.unlock();
        } else |err| {
            std.log.err("Failed to spawn detection thread: {any}", .{err});
        }
    }

    pub fn stop(self: *Perception) void {
        self.mutex.lock();
        if (self.thread != null) {
            self.should_stop = true;
            self.mutex.unlock();

            if (self.thread) |thread| {
                thread.join();
            }

            self.mutex.lock();
            self.thread = null;
        }
        self.mutex.unlock();
    }

    pub fn is_calibrated(self: *Perception) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.calibrated;
    }
};

var initialized = false;
var perception: Perception = undefined;

const Perception2D = struct {
    object: gd.GDExtensionObjectPtr,

    pub fn num_detections(_: *Perception2D) i64 {
        return perception.num_detections();
    }

    pub fn get_detection_score(_: *Perception2D, detection_index: i64, keypoint_index: i64) f64 {
        return perception.get_detection_score(detection_index, keypoint_index);
    }
    pub fn get_detection_keypoint(_: *Perception2D, detection_index: i64, keypoint_index: i64) Vec2 {
        return perception.get_detection_keypoint(detection_index, keypoint_index);
    }

    pub fn start(_: *Perception2D) void {
        if (!initialized) {
            initialized = true;
            perception.start();
        }
    }

    pub fn stop(_: *Perception2D) void {
        return perception.stop();
    }

    pub fn is_calibrated(_: *Perception2D) bool {
        return perception.is_calibrated();
    }
};

fn initModule(data: ?*anyopaque, level: gd.GDExtensionInitializationLevel) callconv(.C) void {
    if (level != gd.GDEXTENSION_INITIALIZATION_SCENE) {
        return;
    }
    _ = data;

    godot.registerClass(Perception2D, "Node2D");
}

fn deinitModule(data: ?*anyopaque, level: gd.GDExtensionInitializationLevel) callconv(.C) void {
    _ = data;
    _ = level;
}

export fn perception_extension_init(
    get_proc_address: gd.GDExtensionInterfaceGetProcAddress,
    lib: gd.GDExtensionClassLibraryPtr,
    init: *gd.GDExtensionInitialization,
) callconv(.C) void {
    godot.initFunctions(get_proc_address, lib);

    init.initialize = initModule;
    init.deinitialize = deinitModule;
    init.minimum_initialization_level = gd.GDEXTENSION_INITIALIZATION_SCENE;
}
