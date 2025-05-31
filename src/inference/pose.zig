const std = @import("std");

const inf = @import("inference.zig");
const Detection = inf.Detection;
const Inference = inf.Inference;

const Camera = @import("../camera/camera.zig").Camera;
const Spsc = @import("../util/spsc_ring.zig").Spsc;

const ffi = @cImport({
    @cInclude("ffi.h");
});

const CHESSBOARD_WIDTH = 7;
const CHESSBOARD_HEIGHT = 4;
const DETECTION_CAPACITY = 20;

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

const DetectionSpsc = Spsc(Detection, DETECTION_CAPACITY * 8);

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

    pub fn nextDetection(self: *PoseDetector) ?Detection {
        return self.output.tryDequeue();
    }

    fn run(self: *PoseDetector) !void {
        var transform = ffi.FfiMat3{};

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
                if (ffi.find_chessboard(calibration_frames[frame_idx], CHESSBOARD_WIDTH, CHESSBOARD_HEIGHT, &transform)) {
                    camera.setFloatMode([2][*]f32{
                        inference.input_buffers[0],
                        inference.input_buffers[1],
                    });
                    calibrated = true;
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

                self.output.enqueue(det) catch {
                    std.log.warn("Detection processing queue full", .{});
                };
            }
        }
    }
};
