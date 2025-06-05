const std = @import("std");

const engine = @import("engine");
const Mat4 = engine.math.Mat4;

comptime {
    _ = engine;
}

const Vertex = struct {
    position: @Vector(3, f32) align(16),
    tex_coord: @Vector(2, f32) align(8),
};

pub fn createChessboard(renderer: *engine.Renderer) engine.Renderer.ImageHandle {
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
    return renderer.createImage(&checkerboard, 1280, 800);
}

fn registerHandler(user_ptr: *anyopaque, callback: engine.Scripting.Function) void {
    var event_handlers: *std.ArrayList(engine.Scripting.Function) = @alignCast(@ptrCast(user_ptr));
    event_handlers.append(callback) catch unreachable;
}

pub fn main() !void {
    var dba = std.heap.DebugAllocator(.{}).init;
    defer {
        if (dba.deinit() == .leak) {
            std.log.err("memory leak detected", .{});
        }
    }
    const allocator = dba.allocator();

    var event_handlers = std.ArrayList(engine.Scripting.Function).init(allocator);
    defer event_handlers.deinit();

    const scripting = engine.Scripting.init(&event_handlers);
    defer scripting.deinit();
    const module = scripting.defineModule("simulo");
    const func = scripting.createFunction(registerHandler);
    scripting.defineFunction(module, "test", func);

    var args = try std.process.argsWithAllocator(allocator);
    args.deinit();

    _ = args.next(); // skip program name
    const script_path = args.next() orelse {
        std.log.err("provide a path to a script", .{});
        return;
    };

    const script_file = std.fs.cwd().readFileAlloc(allocator, script_path, std.math.maxInt(usize)) catch |err| {
        std.log.err("failed to read script file: {}", .{err});
        return;
    };
    defer allocator.free(script_file);

    try scripting.run(script_file, script_path);

    for (event_handlers.items) |handler| {
        scripting.callFunction(&handler);
    }

    const gpu = engine.Gpu.init();
    defer gpu.deinit();

    var window = engine.Window.init(&gpu, "Simulo");
    defer window.deinit();

    var renderer = engine.Renderer.init(&gpu, &window);
    defer renderer.deinit();

    var pose_detector = engine.PoseDetector.init();
    defer pose_detector.stop();
    pose_detector.start() catch unreachable;

    const image = createChessboard(&renderer);
    const material = renderer.createUiMaterial(image, 1.0, 1.0, 1.0);

    const vertices = [_]Vertex{
        .{ .position = .{ 0.0, 0.0, 0.0 }, .tex_coord = .{ 0.0, 0.0 } },
        .{ .position = .{ 1.0, 0.0, 0.0 }, .tex_coord = .{ 1.0, 0.0 } },
        .{ .position = .{ 1.0, 1.0, 0.0 }, .tex_coord = .{ 1.0, 1.0 } },
        .{ .position = .{ 0.0, 1.0, 0.0 }, .tex_coord = .{ 0.0, 1.0 } },
    };
    const mesh = renderer.createMesh(std.mem.asBytes(&vertices), &[_]u16{ 0, 1, 2, 2, 3, 0 });
    const chessboard = renderer.addObject(mesh, Mat4.identity(), material);

    var calibrated = false;
    var tracked_objects = std.AutoHashMap(u64, engine.Renderer.ObjectHandle).init(allocator);
    defer tracked_objects.deinit();

    while (window.poll()) {
        const width: f32 = @floatFromInt(window.getWidth());
        const height: f32 = @floatFromInt(window.getHeight());

        if (calibrated) {
            renderer.setObjectTransform(chessboard, Mat4.scale(.{ 0, 0, 0 }));
        } else {
            renderer.setObjectTransform(chessboard, Mat4.scale(.{ width, height, 1 }));
        }

        const ui_projection = Mat4.ortho(width, height, -1.0, 1.0);
        _ = renderer.render(&ui_projection, &ui_projection);

        while (pose_detector.nextEvent()) |event| {
            const detection = event.detection orelse {
                const object = tracked_objects.get(event.id).?;
                renderer.deleteObject(object);
                if (!tracked_objects.remove(event.id)) {
                    std.log.err("tracked object wasn't deleted", .{});
                }
                continue;
            };

            const left_hand = detection.keypoints[9].pos;
            const translate = Mat4.translate(.{ left_hand[0] * width - 25.0, left_hand[1] * height - 25.0, 0 });
            const scale = Mat4.scale(.{ 50, 50, 1 });
            const transform = translate.matmul(&scale);
            const object = renderer.addObject(mesh, transform, material);
            tracked_objects.put(event.id, object) catch unreachable;

            calibrated = true;
        }
    }
}
