const std = @import("std");

const engine = @import("engine");
const Mat4 = engine.math.Mat4;
const FixedArrayList = @import("../util/fixed_arraylist.zig").FixedArrayList;

const behaviors = @import("behaviors.zig");
const events = @import("events.zig");

comptime {
    _ = engine;
}

const Vertex = struct {
    position: @Vector(3, f32) align(16),
    tex_coord: @Vector(2, f32) align(8),
};

pub const GameObject = struct {
    x: f32,
    y: f32,
    handle: engine.Renderer.ObjectHandle,
    behaviors: std.ArrayListUnmanaged(behaviors.Behavior),
    deleted: bool,

    pub fn init(runtime: *Runtime, self: *GameObject, x_: f32, y_: f32) void {
        self.x = x_;
        self.y = y_;

        const translate = Mat4.translate(.{ self.x, self.y, 0 });
        const scale = Mat4.scale(.{ 5, 5, 1 });
        const transform = translate.matmul(&scale);
        self.handle = runtime.renderer.addObject(runtime.mesh, transform, runtime.material);
        self.behaviors = .{};
        self.deleted = false;

        runtime.objects.append(self) catch unreachable;
    }

    pub fn callEvent(self: *GameObject, runtime: *Runtime, event: *const anyopaque) void {
        for (self.behaviors.items) |behavior| {
            for (0..behavior.num_event_handlers) |i| {
                behavior.event_handlers[i](runtime, behavior.behavior_instance, event);
            }
        }
    }

    pub fn delete(self: *GameObject, runtime: *Runtime) void {
        if (self.deleted) {
            return;
        }

        runtime.renderer.deleteObject(self.handle);
        self.deleted = true;
    }

    pub fn py__init__(user_ptr: *anyopaque, self_any: engine.Scripting.Any, x_: f64, y_: f64) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const self = runtime.scripting.getSelf(GameObject, self_any) orelse return;
        GameObject.init(runtime, self, @floatCast(x_), @floatCast(y_));
    }

    pub fn py_x(user_ptr: *anyopaque, self_any: engine.Scripting.Any) f64 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const self = runtime.scripting.getSelf(GameObject, self_any) orelse return 0.0;
        return @floatCast(self.x);
    }

    pub fn py_y(user_ptr: *anyopaque, self_any: engine.Scripting.Any) f64 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const self = runtime.scripting.getSelf(GameObject, self_any) orelse return 0.0;
        return @floatCast(self.y);
    }

    pub fn py_set_position(user_ptr: *anyopaque, self_any: engine.Scripting.Any, x_: f64, y_: f64) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const self = runtime.scripting.getSelf(GameObject, self_any) orelse return;

        self.x = @floatCast(x_);
        self.y = @floatCast(y_);

        const translate = Mat4.translate(.{ self.x, self.y, 0 });
        const scale = Mat4.scale(.{ 5, 5, 1 });
        const transform = translate.matmul(&scale);
        runtime.renderer.setObjectTransform(self.handle, transform);
    }

    pub fn py_delete(user_ptr: *anyopaque, self_any: engine.Scripting.Any) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const self = runtime.scripting.getSelf(GameObject, self_any) orelse return;
        self.delete(runtime);
    }

    pub fn py_add_behavior(user_ptr: *anyopaque, self_any: engine.Scripting.Any, behavior_any: engine.Scripting.Any) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const self = runtime.scripting.getSelf(GameObject, self_any) orelse return;

        if (!runtime.isNativeBehavior(behavior_any.ty)) {
            return;
        }

        const behavior_derived = runtime.scripting.getRawSelf(behavior_any);
        const behavior: *behaviors.Behavior = @ptrCast(@alignCast(behavior_derived));

        var type_str_buf: [8]u8 = undefined;
        const type_str = std.fmt.bufPrint(&type_str_buf, "{d}", .{behavior_any.ty}) catch unreachable;

        runtime.scripting.keepMemberAlive(
            self_any,
            behavior_any,
            type_str,
        );
        self.behaviors.append(runtime.allocator, behavior.*) catch unreachable;
    }
};

const vertices = [_]Vertex{
    .{ .position = .{ 0.0, 0.0, 0.0 }, .tex_coord = .{ 0.0, 0.0 } },
    .{ .position = .{ 1.0, 0.0, 0.0 }, .tex_coord = .{ 1.0, 0.0 } },
    .{ .position = .{ 1.0, 1.0, 0.0 }, .tex_coord = .{ 1.0, 1.0 } },
    .{ .position = .{ 0.0, 1.0, 0.0 }, .tex_coord = .{ 0.0, 1.0 } },
};

pub const Runtime = struct {
    gpu: engine.Gpu,
    window: engine.Window,
    renderer: engine.Renderer,
    event_handlers: FixedArrayList(engine.Scripting.Function, 16),
    pose_detector: engine.PoseDetector,
    allocator: std.mem.Allocator,

    native_behaviors: std.ArrayList(engine.Scripting.Type),
    scripting: engine.Scripting,
    objects: std.ArrayList(*GameObject),

    material: engine.Renderer.MaterialHandle,
    mesh: engine.Renderer.MeshHandle,
    chessboard: engine.Renderer.ObjectHandle,
    calibrated: bool,

    pub fn init(runtime: *Runtime, allocator: std.mem.Allocator) !void {
        runtime.allocator = allocator;

        runtime.gpu = engine.Gpu.init();
        runtime.window = engine.Window.init(&runtime.gpu, "simulo runtime");
        runtime.renderer = engine.Renderer.init(&runtime.gpu, &runtime.window);
        runtime.event_handlers = FixedArrayList(engine.Scripting.Function, 16).init();
        runtime.pose_detector = engine.PoseDetector.init();
        runtime.calibrated = false;

        runtime.native_behaviors = std.ArrayList(engine.Scripting.Type).init(runtime.allocator);
        runtime.scripting = engine.Scripting.init(runtime, allocator);
        const module = runtime.scripting.defineModule("simulo");
        runtime.scripting.defineFunction(module, "on", Runtime.registerEventHandler);

        _ = try runtime.scripting.defineClass(GameObject, module);
        runtime.scripting.defineMethod(GameObject, "__init__", GameObject.py__init__);
        runtime.scripting.defineMethod(GameObject, "x", GameObject.py_x);
        runtime.scripting.defineMethod(GameObject, "y", GameObject.py_y);
        runtime.scripting.defineMethod(GameObject, "set_position", GameObject.py_set_position);
        runtime.scripting.defineMethod(GameObject, "delete", GameObject.py_delete);
        runtime.scripting.defineMethod(GameObject, "add_behavior", GameObject.py_add_behavior);

        try runtime.native_behaviors.append(try runtime.scripting.defineClass(behaviors.MovementBehavior, module));
        runtime.scripting.defineMethod(behaviors.MovementBehavior, "__init__", behaviors.MovementBehavior.py__init__);

        try runtime.native_behaviors.append(try runtime.scripting.defineClass(behaviors.LifetimeBehavior, module));
        runtime.scripting.defineMethod(behaviors.LifetimeBehavior, "__init__", behaviors.LifetimeBehavior.py__init__);

        runtime.objects = std.ArrayList(*GameObject).init(runtime.allocator);

        const image = createChessboard(&runtime.renderer);
        runtime.material = runtime.renderer.createUiMaterial(image, 1.0, 1.0, 1.0);
        runtime.mesh = runtime.renderer.createMesh(std.mem.asBytes(&vertices), &[_]u16{ 0, 1, 2, 2, 3, 0 });
        runtime.chessboard = runtime.renderer.addObject(runtime.mesh, Mat4.identity(), runtime.material);
    }

    pub fn deinit(self: *Runtime) void {
        self.scripting.deinit();
        self.objects.deinit();
        self.native_behaviors.deinit();

        self.pose_detector.stop();
        self.renderer.deinit();
        self.window.deinit();
        self.gpu.deinit();
    }

    pub fn runScript(self: *Runtime, source: []const u8, file_name: []const u8) !void {
        try self.scripting.run(source, file_name);
    }

    fn isNativeBehavior(self: *const Runtime, ty: engine.Scripting.Type) bool {
        for (self.native_behaviors.items) |behavior| {
            if (behavior == ty) {
                return true;
            }
        }
        return false;
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

    pub fn run(self: *Runtime) !void {
        try self.pose_detector.start();
        var last_time = std.time.milliTimestamp();

        while (self.window.poll()) {
            const now = std.time.milliTimestamp();
            const delta = now - last_time;
            last_time = now;

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

            const deltaf: f32 = @floatFromInt(delta);
            const event = events.UpdateEvent{ .delta = deltaf / 1000.0 };
            for (self.objects.items) |object| {
                object.callEvent(self, &event);
            }

            self.clearDeletedObjects();
        }
    }

    fn processPoseDetections(self: *Runtime, width: f32, height: f32) !void {
        while (self.pose_detector.nextEvent()) |event| {
            const id_i64: i64 = @intCast(event.id);

            const detection = event.detection orelse {
                self.callEvent(.{ id_i64, @as(f64, -1), @as(f64, -1) });
                continue;
            };

            const left_hand = detection.keypoints[9].pos;
            const fx: f64 = @floatCast(left_hand[0] * width);
            const fy: f64 = @floatCast(left_hand[1] * height);
            self.callEvent(.{ id_i64, fx, fy });
            self.calibrated = true;
        }
    }

    fn clearDeletedObjects(self: *Runtime) void {
        var i: usize = 0;
        while (i < self.objects.items.len) {
            const object = self.objects.items[i];
            if (object.deleted) {
                _ = self.objects.swapRemove(i);
            } else {
                i += 1;
            }
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
