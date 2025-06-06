const std = @import("std");

const engine = @import("engine");
const Mat4 = engine.math.Mat4;
const FixedArrayList = @import("../util/fixed_arraylist.zig").FixedArrayList;

comptime {
    _ = engine;
}

const Vertex = struct {
    position: @Vector(3, f32) align(16),
    tex_coord: @Vector(2, f32) align(8),
};

const vertices = [_]Vertex{
    .{ .position = .{ 0.0, 0.0, 0.0 }, .tex_coord = .{ 0.0, 0.0 } },
    .{ .position = .{ 1.0, 0.0, 0.0 }, .tex_coord = .{ 1.0, 0.0 } },
    .{ .position = .{ 1.0, 1.0, 0.0 }, .tex_coord = .{ 1.0, 1.0 } },
    .{ .position = .{ 0.0, 1.0, 0.0 }, .tex_coord = .{ 0.0, 1.0 } },
};

const Runtime = struct {
    gpu: engine.Gpu,
    window: engine.Window,
    renderer: engine.Renderer,
    event_handlers: FixedArrayList(engine.Scripting.Function, 16),
    scripting: engine.Scripting,
    pose_detector: engine.PoseDetector,
    allocator: std.mem.Allocator,

    material: engine.Renderer.MaterialHandle,
    mesh: engine.Renderer.MeshHandle,
    chessboard: engine.Renderer.ObjectHandle,
    tracked_objects: std.AutoHashMap(u64, engine.Renderer.ObjectHandle),
    calibrated: bool,

    fn init(runtime: *Runtime, allocator: std.mem.Allocator) void {
        runtime.allocator = allocator;

        runtime.gpu = engine.Gpu.init();
        runtime.window = engine.Window.init(&runtime.gpu, "simulo runtime");
        runtime.renderer = engine.Renderer.init(&runtime.gpu, &runtime.window);
        runtime.event_handlers = FixedArrayList(engine.Scripting.Function, 16).init();
        runtime.scripting = engine.Scripting.init(runtime);
        runtime.pose_detector = engine.PoseDetector.init();
        runtime.tracked_objects = std.AutoHashMap(u64, engine.Renderer.ObjectHandle).init(allocator);
        runtime.calibrated = false;

        const module = runtime.scripting.defineModule("simulo");
        const func = runtime.scripting.createFunction(Runtime.registerEventHandler);
        runtime.scripting.defineFunction(module, "on", func);

        const image = createChessboard(&runtime.renderer);
        runtime.material = runtime.renderer.createUiMaterial(image, 1.0, 1.0, 1.0);
        runtime.mesh = runtime.renderer.createMesh(std.mem.asBytes(&vertices), &[_]u16{ 0, 1, 2, 2, 3, 0 });
        runtime.chessboard = runtime.renderer.addObject(runtime.mesh, Mat4.identity(), runtime.material);
    }

    fn deinit(self: *Runtime) void {
        self.tracked_objects.deinit();
        self.pose_detector.stop();
        self.scripting.deinit();
        self.renderer.deinit();
        self.window.deinit();
        self.gpu.deinit();
    }

    fn runScript(self: *Runtime, source: []const u8, file_name: []const u8) !void {
        try self.scripting.run(source, file_name);
    }

    fn registerEventHandler(user_ptr: *anyopaque, callback: engine.Scripting.Function) void {
        var runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        runtime.event_handlers.append(callback) catch unreachable;
    }

    fn callEvent(self: *Runtime, args: anytype) void {
        for (self.event_handlers.items()) |handler| {
            self.scripting.callFunction(&handler, args);
        }
    }

    fn run(self: *Runtime) !void {
        try self.pose_detector.start();

        while (self.window.poll()) {
            const width: f32 = @floatFromInt(self.window.getWidth());
            const height: f32 = @floatFromInt(self.window.getHeight());

            if (self.calibrated) {
                self.renderer.setObjectTransform(self.chessboard, Mat4.scale(.{ 0, 0, 0 }));
            } else {
                self.renderer.setObjectTransform(self.chessboard, Mat4.scale(.{ width, height, 1 }));
            }

            const ui_projection = Mat4.ortho(width, height, -1.0, 1.0);
            _ = self.renderer.render(&ui_projection, &ui_projection);

            try self.processPoseDetections(width, height);
        }
    }

    fn processPoseDetections(self: *Runtime, width: f32, height: f32) !void {
        while (self.pose_detector.nextEvent()) |event| {
            const detection = event.detection orelse {
                const object = self.tracked_objects.get(event.id).?;
                self.renderer.deleteObject(object);
                if (!self.tracked_objects.remove(event.id)) {
                    std.log.err("tracked object wasn't deleted", .{});
                }
                continue;
            };

            const left_hand = detection.keypoints[9].pos;
            const translate = Mat4.translate(.{ left_hand[0] * width - 25.0, left_hand[1] * height - 25.0, 0 });
            const scale = Mat4.scale(.{ 50, 50, 1 });
            const transform = translate.matmul(&scale);

            const id_i64: i64 = @intCast(event.id);
            self.callEvent(.{ id_i64, left_hand[0], left_hand[1] });

            const object = self.renderer.addObject(self.mesh, transform, self.material);
            try self.tracked_objects.put(event.id, object);

            self.calibrated = true;
        }
    }
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

pub fn main() !void {
    var dba = std.heap.DebugAllocator(.{}).init;
    defer {
        if (dba.deinit() == .leak) {
            std.log.err("memory leak detected", .{});
        }
    }
    const allocator = dba.allocator();

    var runtime: Runtime = undefined;
    Runtime.init(&runtime, allocator);
    defer runtime.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

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

    try runtime.runScript(script_file, script_path);
    try runtime.run();
}
