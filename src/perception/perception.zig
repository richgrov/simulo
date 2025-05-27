const engine = @import("engine");
const std = @import("std");

comptime {
    _ = engine;
}
const ffi = @cImport({
    @cInclude("ffi.h");
});

const chessboardWidth = 7;
const chessboardHeight = 4;

const Vec2 = @Vector(2, f32);
const Vec3 = @Vector(3, f32);

const UiVertex = struct {
    position: Vec3,
    tex_coord: Vec2,
};

fn perspective_transform(x: f32, y: f32, transform: *ffi.OpenCvMat) @Vector(2, f32) {
    const real_y = (y - (640 - 480) / 2);
    const res = ffi.perspective_transform(x, real_y, transform);
    return @Vector(2, f32){ res.x, res.y };
}

fn perception_loop() !void {
    var detections: [20]engine.Detection = undefined;
    const transform = ffi.create_opencv_mat(3, 3).?;

    const calibration_frames = [2]*ffi.OpenCvMat{
        ffi.create_opencv_mat(480, 640).?,
        ffi.create_opencv_mat(480, 640).?,
    };

    defer ffi.destroy_opencv_mat(calibration_frames[0]);
    defer ffi.destroy_opencv_mat(calibration_frames[1]);
    defer ffi.destroy_opencv_mat(transform);

    var calibrated = false;

    var camera = try engine.Camera.init([2][*]u8{
        ffi.get_opencv_mat_data(calibration_frames[0]),
        ffi.get_opencv_mat_data(calibration_frames[1]),
    });
    defer camera.deinit();

    var inference = try engine.Inference.init();
    defer inference.deinit();

    while (true) {
        const frame_idx = camera.swapBuffers();

        if (!calibrated) {
            if (ffi.find_chessboard(calibration_frames[frame_idx], chessboardWidth, chessboardHeight, transform)) {
                camera.setFloatMode([2][*]f32{
                    inference.input_buffers[0],
                    inference.input_buffers[1],
                });
                calibrated = true;
                std.log.info("Calibrated", .{});
            }
            continue;
        }

        const n_dets = try inference.run(frame_idx, &detections);
        for (0..n_dets) |i| {
            const det = &detections[i];
            const pos = perspective_transform(det.pos[0], det.pos[1], transform);
            const size = perspective_transform(det.size[0], det.size[1], transform);
            std.log.info("Detection {any} x={d:.2}, y={d:.2}, w={d:.2}, h={d:.2}, s={d:.2}", .{
                i,
                pos[0],
                pos[1],
                size[0],
                size[1],
                det.score,
            });

            for (0..det.keypoints.len) |k| {
                const kp_pos = perspective_transform(det.keypoints[k].pos[0], det.keypoints[k].pos[1], transform);
                std.log.info(" {any} {d:.2}, {d:.2}, {d:.2}", .{
                    k,
                    kp_pos[0],
                    kp_pos[1],
                    det.keypoints[k].score,
                });
            }
        }
    }
}

pub fn main() !void {
    const gpu = engine.Gpu.init();
    defer gpu.deinit();

    var window = engine.Window.init(&gpu, "Simulo");
    defer window.deinit();

    var renderer = engine.Renderer.init(&gpu, &window);
    defer renderer.deinit();

    var checkerboard: [1280 * 800]u8 = undefined;
    for (0..1280) |x| {
        for (0..800) |y| {
            const x_square = x / 160;
            const y_square = y / 160;
            if (x_square % 2 == y_square % 2) {
                checkerboard[y * 1280 + x] = 0xFF;
            } else {
                checkerboard[y * 1280 + x] = 0x00;
            }
        }
    }
    const image = renderer.createImage(&checkerboard, 1280, 800);

    const material = renderer.createUiMaterial(image, 1.0, 1.0, 1.0);

    const vertices = [_]UiVertex{
        .{ .position = .{ -1.0, -1.0, 0.0 }, .tex_coord = .{ 0.0, 0.0 } },
        .{ .position = .{ 1.0, -1.0, 0.0 }, .tex_coord = .{ 1.0, 0.0 } },
        .{ .position = .{ 1.0, 1.0, 0.0 }, .tex_coord = .{ 1.0, 1.0 } },
        .{ .position = .{ -1.0, 1.0, 0.0 }, .tex_coord = .{ 0.0, 1.0 } },
    };
    const mesh = renderer.createMesh(std.mem.asBytes(&vertices), &[_]u16{ 0, 1, 2, 2, 3, 0 });

    const transform = [16]f32{
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    };
    _ = renderer.addObject(mesh, transform, material);

    const mvp = [16]f32{
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    };

    const thread = try std.Thread.spawn(.{}, perception_loop, .{});
    defer thread.join();

    while (window.poll()) {
        _ = renderer.render(mvp, mvp);
        std.time.sleep(std.time.ns_per_ms);
    }
}
