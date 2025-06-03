const std = @import("std");

const inf = @import("inference.zig");
const Detection = inf.Detection;
const Inference = inf.Inference;

const Camera = @import("../camera/camera.zig").Camera;
const Spsc = @import("../util/spsc_ring.zig").Spsc;
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
    id: u32,
    detection: ?Detection,
};

const DetectionSpsc = Spsc(PoseEvent, DETECTION_CAPACITY * 8);

pub const PoseDetector = struct {
    output: DetectionSpsc,
    running: bool,
    thread: std.Thread,

    pub fn init() PoseDetector {
        return PoseDetector{
            .output = DetectionSpsc.init(),
            .running = true,
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

            for (0..n_dets) |i| {
                var det = local_detections[i];
                det.pos = perspective_transform(det.pos[0], det.pos[1], &transform);
                det.size = perspective_transform(det.size[0], det.size[1], &transform);

                for (0..det.keypoints.len) |k| {
                    const kp = det.keypoints[k];
                    const kp_pos = perspective_transform(kp.pos[0], kp.pos[1], &transform);
                    det.keypoints[k].pos = kp_pos;
                    det.keypoints[k].score = @floatCast(kp.score);
                }

                self.output.enqueue(PoseEvent{ .id = 0, .detection = det }) catch {
                    std.log.warn("Detection processing queue full", .{});
                };
            }
        }
    }
};
