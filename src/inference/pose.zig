const std = @import("std");

const inf = @import("inference.zig");
const Detection = inf.Detection;
const Inference = inf.Inference;
const Box = inf.Box;

const Camera = @import("../camera/camera.zig").Camera;
const Spsc = @import("../util/spsc_ring.zig").Spsc;
const FixedArrayList = @import("../util/fixed_arraylist.zig").FixedArrayList;
const DMat3 = @import("../math/matrix.zig").DMat3;

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

pub const PoseEvent = struct {
    id: u64,
    detection: ?Detection,
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

    pub fn init() PoseDetector {
        return PoseDetector{
            .output = DetectionSpsc.init(),
            .running = true,
            .last_tracked_boxes = FixedArrayList(TrackedBox, DETECTION_CAPACITY * 2).init(),
            .thread = undefined,
        };
    }

    pub fn start(self: *PoseDetector) !void {
        @atomicStore(bool, &self.running, true, .seq_cst);
        self.thread = try std.Thread.spawn(.{}, PoseDetector.run, .{self});
    }

    pub fn stop(self: *PoseDetector) void {
        @atomicStore(bool, &self.running, false, .seq_cst);
        self.thread.join();
    }

    pub fn nextEvent(self: *PoseDetector) ?PoseEvent {
        return self.output.tryDequeue();
    }

    fn run(self: *PoseDetector) !void {
        var transform: DMat3 = undefined;

        const calibration_frames = [2]*ffi.OpenCvMat{
            ffi.create_opencv_mat(480, 640).?,
            ffi.create_opencv_mat(480, 640).?,
        };

        defer ffi.destroy_opencv_mat(calibration_frames[0]);
        defer ffi.destroy_opencv_mat(calibration_frames[1]);

        var calibrated = false;

        var camera = try Camera.init([2][*]u8{
            ffi.get_opencv_mat_data(calibration_frames[0]),
            ffi.get_opencv_mat_data(calibration_frames[1]),
        });
        defer camera.deinit();

        var inference = try Inference.init();
        defer inference.deinit();

        while (@atomicLoad(bool, &self.running, .monotonic)) {
            const frame_idx = camera.swapBuffers();

            if (!calibrated) {
                var transform_out: ffi.FfiMat3 = undefined;
                if (ffi.find_chessboard(calibration_frames[frame_idx], CHESSBOARD_WIDTH, CHESSBOARD_HEIGHT, &transform_out)) {
                    camera.setFloatMode([2][*]f32{
                        inference.input_buffers[0],
                        inference.input_buffers[1],
                    });
                    calibrated = true;
                    transform = DMat3.fromRowMajorPtr(&transform_out.data);
                }
                continue;
            }

            var local_detections: [DETECTION_CAPACITY]Detection = undefined;
            const n_dets = try inference.run(frame_idx, &local_detections);

            var next_tracked_boxes = FixedArrayList(TrackedBox, DETECTION_CAPACITY * 2).init();

            for (0..n_dets) |i| {
                var det = local_detections[i];
                const tracking_id = self.nearestPreviousDetection(&det.box) orelse self.nextDetectionId();
                next_tracked_boxes.append(.{ .id = tracking_id, .box = det.box }) catch {
                    std.log.err("impossible: next track list full", .{});
                };

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

                self.output.enqueue(PoseEvent{ .id = tracking_id, .detection = det }) catch {
                    std.log.warn("Detection processing queue full", .{});
                };
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
                    self.output.enqueue(PoseEvent{ .id = id, .detection = null }) catch {
                        std.log.warn("Detection processing queue full", .{});
                    };
                }
            }

            self.last_tracked_boxes = next_tracked_boxes;
        }
    }

    fn nearestPreviousDetection(_: *const PoseDetector, _: *const Box) ?u64 {
        return null;
    }

    fn nextDetectionId(self: *PoseDetector) u64 {
        const id = self.next_tracked_box_id;
        self.next_tracked_box_id += 1;
        return id;
    }
};
