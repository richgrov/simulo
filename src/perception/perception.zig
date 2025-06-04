const std = @import("std");

const engine = @import("engine");

comptime {
    _ = engine;
}
const ffi = @cImport({
    @cInclude("ffi.h");
});

const Vec2 = @Vector(2, f32);
const Vec3 = @Vector(3, f32);
const Mat4 = engine.math.Mat4;

const UiVertex = struct {
    position: Vec3,
    tex_coord: Vec2,
};

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
        .{ .position = .{ 0.0, 0.0, 0.0 }, .tex_coord = .{ 0.0, 0.0 } },
        .{ .position = .{ 1.0, 0.0, 0.0 }, .tex_coord = .{ 1.0, 0.0 } },
        .{ .position = .{ 1.0, 1.0, 0.0 }, .tex_coord = .{ 1.0, 1.0 } },
        .{ .position = .{ 0.0, 1.0, 0.0 }, .tex_coord = .{ 0.0, 1.0 } },
    };
    const mesh = renderer.createMesh(std.mem.asBytes(&vertices), &[_]u16{ 0, 1, 2, 2, 3, 0 });
    const chessboard = renderer.addObject(mesh, Mat4.identity(), material);

    const target_mesh = renderer.createMesh(std.mem.asBytes(&vertices), &[_]u16{ 0, 1, 2, 2, 3, 0 });
    const target = renderer.addObject(target_mesh, Mat4.identity(), material);

    var detector = engine.PoseDetector.init();
    detector.start() catch unreachable;
    defer detector.stop();

    var calibrated = false;

    while (window.poll()) {
        const width: f32 = @floatFromInt(window.getWidth());
        const height: f32 = @floatFromInt(window.getHeight());

        if (calibrated) {
            renderer.setObjectTransform(chessboard, Mat4.scale(.{ 0.0, 0.0, 1.0 }));
        } else {
            renderer.setObjectTransform(chessboard, Mat4.scale(.{ width, height, 1.0 }));
        }

        const mvp = Mat4.ortho(width, height, -1.0, 1.0);
        _ = renderer.render(&mvp, &mvp);

        while (detector.nextEvent()) |event| {
            calibrated = true;

            const detection = event.detection orelse continue;
            std.log.info("Detection x={d:.2}, y={d:.2}, w={d:.2}, h={d:.2}, s={d:.2}", .{
                detection.pos[0],
                detection.pos[1],
                detection.size[0],
                detection.size[1],
                detection.score,
            });

            for (0..detection.keypoints.len) |k| {
                const kp = detection.keypoints[k];
                std.log.info("  {any} {d:.2}, {d:.2}, {d:.2}", .{ k, kp.pos[0], kp.pos[1], kp.score });
            }

            const hand = detection.keypoints[9].pos;
            renderer.setObjectTransform(target, Mat4.scale(.{ hand[0] * width, (1.0 - hand[1]) * height, 1.0 }));
        }

        std.time.sleep(std.time.ns_per_ms);
    }
}
