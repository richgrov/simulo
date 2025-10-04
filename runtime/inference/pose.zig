const std = @import("std");
const build_options = @import("build_options");
const Logger = @import("../log.zig").Logger;

const engine = @import("engine");
const profile = engine.profiler;

const util = @import("util");
const Spsc = util.Spsc;
const FixedArrayList = util.FixedArrayList;

const inf = @import("inference.zig");
const Detection = inf.Detection;
const Inference = inf.Inference;
const Box = inf.Box;

const Calibrator = @import("calibrate.zig").Calibrator;

const tracking = @import("tracking.zig");
const BoxTracker = tracking.BoxTracker;
const TrackingEvent = tracking.TrackingEvent;

const Camera = @import("../camera/camera.zig").Camera;
const DMat3 = @import("engine").math.DMat3;

const time_until_low_power = @as(i64, 10000);
var last_detection_time = @as(i64, 0);
var is_in_low_power = false;

const ffi = @cImport({
    @cInclude("ffi.h");
});

const CHESSBOARD_WIDTH = 7;
const CHESSBOARD_HEIGHT = 4;
const DETECTION_CAPACITY = 20;

fn perspective_transform(x: f32, y: f32, transform: *const DMat3) @Vector(2, f32) {
    const real_y = (y - (640 - 480) / 2);
    const res = transform.vecmul(.{ @floatCast(x), @floatCast(real_y), 1 });
    return @Vector(2, f32){ @floatCast(res[0] / res[2]), @floatCast(res[1] / res[2]) };
}

const Profiler = profile.Profiler("pose", enum {
    camera_swap,
    calibrate,
    inference,
    tracking,
});

pub const PoseEvent = union(enum) {
    calibration_background_set: void,
    calibration_calibrated: void,
    move: struct {
        id: u64,
        detection: Detection,
    },
    lost: u64,
    fault: struct {
        category: enum {
            calibrate_init,
            camera_init,
            inference_init,
            inference_run,
            camera_stall,
            background_swap,
            set_background,
            camera_swap,
            calibrate,
        },
        err: anyerror,
    },
};

const DetectionSpsc = Spsc(PoseEvent, DETECTION_CAPACITY * 8);

pub const PoseDetector = struct {
    output: DetectionSpsc,
    running: bool,
    thread: std.Thread,
    profiler: Profiler,
    logger: Logger("pose", 2048),
    camera_id: []const u8,

    pub fn init(camera_id: []const u8) PoseDetector {
        return PoseDetector{
            .output = DetectionSpsc.init(),
            .running = false,
            .thread = undefined,
            .profiler = Profiler.init(),
            .logger = Logger("pose", 2048).init(),
            .camera_id = camera_id,
        };
    }

    pub fn start(self: *PoseDetector) !void {
        const started = @cmpxchgStrong(bool, &self.running, false, true, .seq_cst, .seq_cst) == null;
        if (started) {
            self.thread = try std.Thread.spawn(.{}, PoseDetector.run, .{self});
            last_detection_time = std.time.milliTimestamp();
        }
    }

    pub fn stop(self: *PoseDetector) void {
        const stopped = @cmpxchgStrong(bool, &self.running, true, false, .seq_cst, .seq_cst) == null;
        if (stopped) {
            self.thread.join();
        }
    }

    pub fn nextEvent(self: *PoseDetector) ?PoseEvent {
        return self.output.tryDequeue();
    }

    fn run(self: *PoseDetector) void {
        var transform: DMat3 = undefined;

        var calibrated = false;
        var calibrator = Calibrator.init() catch |err| {
            self.logEvent(.{ .fault = .{ .category = .calibrate_init, .err = err } });
            return;
        };
        defer calibrator.deinit();

        var camera = Camera.init(calibrator.mats(), self.camera_id) catch |err| {
            self.logEvent(.{ .fault = .{ .category = .camera_init, .err = err } });
            return;
        };
        defer camera.deinit();

        var inference = Inference.init() catch |err| {
            self.logEvent(.{ .fault = .{ .category = .inference_init, .err = err } });
            return;
        };
        defer inference.deinit();

        var tracker = BoxTracker.init();

        // ignore first few frames as they may contain initialization artifacts
        for (0..3) |_| {
            _ = camera.swapBuffers() catch |err| {
                self.logEvent(.{ .fault = .{ .category = .camera_stall, .err = err } });
                return;
            };
        }

        const background_frame_idx = camera.swapBuffers() catch |err| {
            self.logEvent(.{ .fault = .{ .category = .background_swap, .err = err } });
            return;
        };

        calibrator.setBackground(background_frame_idx) catch |err| {
            self.logEvent(.{ .fault = .{ .category = .set_background, .err = err } });
            return;
        };
        self.logEvent(.calibration_background_set);

        while (@atomicLoad(bool, &self.running, .monotonic)) {
            defer self.profiler.reset();

            const frame_idx = camera.swapBuffers() catch |err| {
                self.logEvent(.{ .fault = .{ .category = .camera_swap, .err = err } });
                continue;
            };

            self.profiler.log(.camera_swap);

            if (!calibrated) {
                const maybe_transform = calibrator.calibrate(frame_idx, CHESSBOARD_WIDTH, CHESSBOARD_HEIGHT) catch |err| {
                    self.logEvent(.{ .fault = .{ .category = .calibrate, .err = err } });
                    continue;
                };

                if (maybe_transform) |out_transform| {
                    transform = out_transform;
                    camera.setFloatMode([2][*]f32{
                        inference.input_buffers[0],
                        inference.input_buffers[1],
                    });
                    calibrated = true;
                    self.logEvent(.calibration_calibrated);
                }

                self.profiler.log(.calibrate);
                continue;
            }

            if (std.time.milliTimestamp() - last_detection_time >= time_until_low_power) {
                if (!is_in_low_power) {
                    self.logger.debug("entering low power mode", .{});
                    is_in_low_power = true;
                }
                std.Thread.sleep(std.time.ns_per_s / 2);
            } else if (is_in_low_power) {
                self.logger.debug("exiting low power mode", .{});
                is_in_low_power = false;
            }

            var local_detections: [DETECTION_CAPACITY]Detection = undefined;
            const n_dets = inference.run(frame_idx, &local_detections) catch |err| {
                self.logEvent(.{ .fault = .{ .category = .inference_run, .err = err } });
                continue;
            };

            self.profiler.log(.inference);

            const tracking_events = tracker.update(local_detections[0..n_dets]);
            const now = std.time.milliTimestamp();
            for (tracking_events) |event| {
                switch (event) {
                    .moved => |moved| {
                        last_detection_time = now;

                        var det = local_detections[moved.new_box];

                        const transformed_pos = perspective_transform(det.box.pos[0], det.box.pos[1], &transform);
                        det.box.pos = .{ transformed_pos[0], 1 - transformed_pos[1] };
                        det.box.size = perspective_transform(det.box.size[0], det.box.size[1], &transform);

                        for (0..det.keypoints.len) |k| {
                            const kp = det.keypoints[k];
                            const transformed_kp_pos = perspective_transform(kp.pos[0], kp.pos[1], &transform);
                            const kp_pos = .{ transformed_kp_pos[0], 1 - transformed_kp_pos[1] };
                            det.keypoints[k].pos = kp_pos;
                            det.keypoints[k].score = @floatCast(kp.score);
                        }

                        self.logEvent(.{ .move = .{ .id = moved.id, .detection = det } });
                    },
                    .lost => |id| {
                        self.logEvent(.{ .lost = id });
                    },
                }
            }

            self.profiler.log(.tracking);
        }
    }

    fn logEvent(self: *PoseDetector, event: PoseEvent) void {
        self.output.enqueue(event) catch {
            self.logger.warn("detection output message queue full", .{});
        };
    }
};
