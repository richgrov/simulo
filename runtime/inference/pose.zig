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

const Profiler = profile.Profiler("pose", enum {
    camera_swap,
    calibrate,
    inference,
    tracking,
});

pub const PoseEvent = union(enum) {
    ready_to_calibrate: void,
    calibrated: DMat3,
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

pub const DetectionSpsc = Spsc(PoseEvent, DETECTION_CAPACITY * 8);

pub const PoseDetector = struct {
    outputs: util.FixedArrayList(*DetectionSpsc, 8),
    running: bool,
    thread: std.Thread,
    profiler: Profiler,
    logger: Logger("pose", 2048),
    camera_id: util.FixedArrayList(u8, 64),
    calibrated: bool = false,

    pub fn init(camera_id: []const u8) !PoseDetector {
        return PoseDetector{
            .outputs = util.FixedArrayList(*DetectionSpsc, 8).init(),
            .running = false,
            .thread = undefined,
            .profiler = Profiler.init(),
            .logger = Logger("pose", 2048).init(),
            .camera_id = util.FixedArrayList(u8, 64).initFrom(camera_id) catch return error.CameraPathTooLong,
        };
    }

    pub fn start(self: *PoseDetector, needs_calibrate: bool) !void {
        const started = @cmpxchgStrong(bool, &self.running, false, true, .seq_cst, .seq_cst) == null;
        if (started) {
            self.calibrated = !needs_calibrate;
            self.thread = try std.Thread.spawn(.{}, PoseDetector.run, .{self});
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
        var calibrator = Calibrator.init() catch |err| {
            self.logger.err("failed to initialize calibrator: {s}", .{@errorName(err)});
            return;
        };
        defer calibrator.deinit();

        var camera = Camera.init(calibrator.mats(), self.camera_id.items()) catch |err| {
            self.logger.err("failed to initialize pose camera at '{s}': {s}", .{ self.camera_id.items(), @errorName(err) });
            return;
        };
        defer camera.deinit();

        var inference = Inference.init() catch |err| {
            self.logger.err("failed to initialize inference: {s}", .{@errorName(err)});
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

        if (!self.calibrated) {
            const background_frame_idx = camera.swapBuffers() catch |err| {
                self.logger.err("failed to swap buffers: {s}", .{@errorName(err)});
                return;
            };

            calibrator.setBackground(background_frame_idx) catch |err| {
                self.logEvent(.{ .fault = .{ .category = .set_background, .err = err } });
                return;
            };
            self.logEvent(.ready_to_calibrate);
        } else {
            camera.setFloatMode([2][*]f32{
                inference.input_buffers[0],
                inference.input_buffers[1],
            });
        }

        while (@atomicLoad(bool, &self.running, .monotonic)) {
            defer self.profiler.reset();

            const frame_idx = camera.swapBuffers() catch |err| {
                self.logEvent(.{ .fault = .{ .category = .camera_swap, .err = err } });
                continue;
            };

            self.profiler.log(.camera_swap);

            if (!self.calibrated) {
                const maybe_transform = calibrator.calibrate(frame_idx, CHESSBOARD_WIDTH, CHESSBOARD_HEIGHT) catch |err| {
                    self.logger.err("calibration failed: {s}", .{@errorName(err)});
                    continue;
                };

                if (maybe_transform) |out_transform| {
                    camera.setFloatMode([2][*]f32{
                        inference.input_buffers[0],
                        inference.input_buffers[1],
                    });
                    self.logEvent(.{ .calibrated = out_transform });
                }

                self.profiler.log(.calibrate);
                continue;
            }

            last_detection_time = std.time.milliTimestamp();
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

                        const det = local_detections[moved.new_box];
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
        for (self.outputs.items(), 0..) |output, i| {
            output.enqueue(event) catch {
                self.logger.warn("detection output message queue {d} full", .{i});
            };
        }
    }
};
