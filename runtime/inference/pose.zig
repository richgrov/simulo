const std = @import("std");
const build_options = @import("build_options");

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

const Camera = @import("../camera/camera.zig").Camera;
const DMat3 = @import("engine").math.DMat3;

const time_until_low_power = @as(i64, 10000);
var last_detection_time = @as(i64, 0);

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
    calibrated: void,
    move: struct {
        id: u64,
        detection: Detection,
    },
    lost: u64,
    profile: profile.Logs,
    fault: struct {
        category: enum {
            camera_init,
            inference_init,
            inference_run,
            camera_swap,
        },
        err: anyerror,
    },
};

const TrackedBox = struct {
    box: Box,
    id: u64,
};

const DetectionSpsc = Spsc(PoseEvent, DETECTION_CAPACITY * 8);

pub const PoseDetector = struct {
    output: DetectionSpsc,
    running: bool,
    last_tracked_boxes: FixedArrayList(TrackedBox, DETECTION_CAPACITY * 2),
    next_tracked_box_id: u64 = 0,
    thread: std.Thread,
    profiler: Profiler,

    pub fn init() PoseDetector {
        return PoseDetector{
            .output = DetectionSpsc.init(),
            .running = false,
            .last_tracked_boxes = FixedArrayList(TrackedBox, DETECTION_CAPACITY * 2).init(),
            .thread = undefined,
            .profiler = Profiler.init(),
        };
    }

    pub fn start(self: *PoseDetector) !void {
        @atomicStore(bool, &self.running, true, .seq_cst);
        self.thread = try std.Thread.spawn(.{}, PoseDetector.run, .{self});
        last_detection_time = std.time.milliTimestamp();
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
        var calibrator = Calibrator.init();
        defer calibrator.deinit();

        var camera = Camera.init(calibrator.buffers()) catch |err| {
            self.logEvent(.{ .fault = .{ .category = .camera_init, .err = err } });
            return;
        };
        defer camera.deinit();

        var inference = Inference.init() catch |err| {
            self.logEvent(.{ .fault = .{ .category = .inference_init, .err = err } });
            return;
        };
        defer inference.deinit();

        while (@atomicLoad(bool, &self.running, .monotonic)) {
            // Having this line at the end of the loop could result in errors continuing early and
            // preventing the profiler from being reset (filling the log buffer). So do it here to
            // ensure it's always reset.
            self.logEvent(.{ .profile = self.profiler.end() });

            if (std.time.milliTimestamp() - last_detection_time >= time_until_low_power) {
                std.Thread.sleep(std.time.ns_per_s / 2);
            }

            const frame_idx = camera.swapBuffers() catch |err| {
                self.logEvent(.{ .fault = .{ .category = .camera_swap, .err = err } });
                continue;
            };

            self.profiler.log(.camera_swap);

            if (!calibrated) {
                if (calibrator.calibrate(frame_idx, CHESSBOARD_WIDTH, CHESSBOARD_HEIGHT, &transform)) {
                    camera.setFloatMode([2][*]f32{
                        inference.input_buffers[0],
                        inference.input_buffers[1],
                    });
                    calibrated = true;
                    self.logEvent(.calibrated);
                }

                self.profiler.log(.calibrate);
                continue;
            }

            var local_detections: [DETECTION_CAPACITY]Detection = undefined;
            const n_dets = inference.run(frame_idx, &local_detections) catch |err| {
                self.logEvent(.{ .fault = .{ .category = .inference_run, .err = err } });
                continue;
            };

            self.profiler.log(.inference);

            var next_tracked_boxes = FixedArrayList(TrackedBox, DETECTION_CAPACITY * 2).init();

            for (0..n_dets) |i| {
                var det = local_detections[i];
                const tracking_id = self.nearestPreviousDetection(&det.box) orelse self.nextDetectionId();
                next_tracked_boxes.append(.{ .id = tracking_id, .box = det.box }) catch unreachable;

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

                self.logEvent(.{ .move = .{ .id = tracking_id, .detection = det } });
            }

            for (0..self.last_tracked_boxes.len) |i| {
                const id = self.last_tracked_boxes.data[i].id;
                var survived = false;
                for (0..next_tracked_boxes.len) |j| {
                    if (next_tracked_boxes.data[j].id == id) {
                        survived = true;
                        break;
                    }
                }
                if (!survived) {
                    self.logEvent(.{ .lost = id });
                }
            }

            self.last_tracked_boxes = next_tracked_boxes;
            self.profiler.log(.tracking);
        }
    }

    fn nearestPreviousDetection(self: *PoseDetector, box: *const Box) ?u64 {
        var closest_distance: f32 = std.math.floatMax(f32);
        var closest_id: ?u64 = null;

        last_detection_time = std.time.milliTimestamp();

        for (self.last_tracked_boxes.items()) |other| {
            const diff = box.pos - other.box.pos;
            const distance = diff[0] * diff[0] + diff[1] * diff[1];
            if (distance < closest_distance) {
                closest_distance = distance;
                closest_id = other.id;
            }
        }

        return closest_id;
    }

    fn nextDetectionId(self: *PoseDetector) u64 {
        const id = self.next_tracked_box_id;
        self.next_tracked_box_id += 1;
        return id;
    }

    fn logEvent(self: *PoseDetector, event: PoseEvent) void {
        self.output.enqueue(event) catch {
            std.log.warn("detection output message queue full", .{});
        };
    }
};
