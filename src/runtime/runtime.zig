const std = @import("std");

const engine = @import("engine");
const reflect = engine.utils.reflect;
const Mat4 = engine.math.Mat4;
const FixedArrayList = @import("../util/fixed_arraylist.zig").FixedArrayList;

const behaviors = @import("behaviors.zig");
const events = @import("events.zig");

const Wasm = engine.Wasm;

comptime {
    _ = engine;
}

const Vertex = struct {
    position: @Vector(3, f32) align(16),
    tex_coord: @Vector(2, f32) align(8),
};

const ScriptingBehavior = struct {
    name: []const u8,
    method: engine.Scripting.Method,
};

pub const GameObject = struct {
    pos: @Vector(3, f32) align(8), // TODO: probably causes performance issues, but PocketPy can't allocate align(16)
    scale: @Vector(3, f32) align(8),
    handle: engine.Renderer.ObjectHandle,
    scripting_behaviors: std.ArrayListUnmanaged(ScriptingBehavior),
    native_behaviors: std.ArrayListUnmanaged(behaviors.Behavior),
    deleted: bool,

    pub fn init(runtime: *Runtime, self: *GameObject, x_: f32, y_: f32) void {
        self.pos = .{ x_, y_, 0 };
        self.scale = .{ 5, 5, 1 };
        const transform = self.calculateTransform();
        self.handle = runtime.renderer.addObject(runtime.mesh, transform, runtime.material);
        self.scripting_behaviors = .{};
        self.native_behaviors = .{};
        self.deleted = false;

        _ = runtime.objects.insert(self) catch unreachable;
    }

    pub fn callEvent(self: *GameObject, runtime: *Runtime, event: anytype) void {
        const EventType = @TypeOf(event);

        const struct_type, const event_name = switch (@typeInfo(EventType)) {
            .pointer => |ptr| .{ reflect.typeId(ptr.child), ptr.child.name },
            else => @compileError("event must be a pointer to a struct"),
        };

        for (self.scripting_behaviors.items) |behavior| {
            if (!std.mem.eql(u8, behavior.name, event_name)) {
                continue;
            }

            runtime.scripting.callMethod(behavior.method, event.toScriptingArgs());
        }

        for (self.native_behaviors.items) |behavior| {
            for (0..behavior.num_event_handlers) |i| {
                if (behavior.event_handler_types[i] != struct_type) {
                    continue;
                }

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

    pub fn calculateTransform(self: *GameObject) Mat4 {
        const translate = Mat4.translate(.{ self.pos[0], self.pos[1], self.pos[2] });
        const scale = Mat4.scale(.{ self.scale[0], self.scale[1], self.scale[2] });
        return translate.matmul(&scale);
    }

    pub fn py__init__(user_ptr: *anyopaque, self_any: engine.Scripting.Any, x_: f64, y_: f64) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const self = runtime.scripting.getSelf(GameObject, self_any) orelse return;
        GameObject.init(runtime, self, @floatCast(x_), @floatCast(y_));
    }

    pub fn py_x(user_ptr: *anyopaque, self_any: engine.Scripting.Any) f64 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const self = runtime.scripting.getSelf(GameObject, self_any) orelse return 0.0;
        return @floatCast(self.pos[0]);
    }

    pub fn py_y(user_ptr: *anyopaque, self_any: engine.Scripting.Any) f64 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const self = runtime.scripting.getSelf(GameObject, self_any) orelse return 0.0;
        return @floatCast(self.pos[1]);
    }

    pub fn py_set_position(user_ptr: *anyopaque, self_any: engine.Scripting.Any, x_: f64, y_: f64) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const self = runtime.scripting.getSelf(GameObject, self_any) orelse return;
        self.pos = .{ @floatCast(x_), @floatCast(y_), 0 };
        runtime.renderer.setObjectTransform(self.handle, self.calculateTransform());
    }

    pub fn py_x_scale(user_ptr: *anyopaque, self_any: engine.Scripting.Any) f64 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const self = runtime.scripting.getSelf(GameObject, self_any) orelse return 0.0;
        return @floatCast(self.scale[0]);
    }

    pub fn py_y_scale(user_ptr: *anyopaque, self_any: engine.Scripting.Any) f64 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const self = runtime.scripting.getSelf(GameObject, self_any) orelse return 0.0;
        return @floatCast(self.scale[1]);
    }

    pub fn py_set_scale(user_ptr: *anyopaque, self_any: engine.Scripting.Any, x: f64, y: f64) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const self = runtime.scripting.getSelf(GameObject, self_any) orelse return;
        self.scale = .{ @floatCast(x), @floatCast(y), 1 };
        runtime.renderer.setObjectTransform(self.handle, self.calculateTransform());
    }

    pub fn py_delete(user_ptr: *anyopaque, self_any: engine.Scripting.Any) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const self = runtime.scripting.getSelf(GameObject, self_any) orelse return;
        self.delete(runtime);
    }

    pub fn py_add_behavior(user_ptr: *anyopaque, self_any: engine.Scripting.Any, behavior_any: engine.Scripting.Any) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const self = runtime.scripting.getSelf(GameObject, self_any) orelse return;

        var type_str_buf: [8]u8 = undefined;
        const type_str = std.fmt.bufPrint(&type_str_buf, "{d}", .{behavior_any.ty}) catch unreachable;

        runtime.scripting.keepMemberAlive(
            self_any,
            behavior_any,
            type_str,
        );

        if (runtime.isNativeBehavior(behavior_any.ty)) {
            const behavior_derived = runtime.scripting.getRawSelf(behavior_any);
            const behavior: *behaviors.Behavior = @ptrCast(@alignCast(behavior_derived));
            self.native_behaviors.append(runtime.allocator, behavior.*) catch unreachable;
        } else {
            var method_names: [32][]const u8 = undefined;
            var methods: [32]engine.Scripting.Method = undefined;
            const num_methods = runtime.scripting.getMethods(behavior_any, &method_names, &methods);

            for (0..num_methods) |i| {
                const method_name = method_names[i];
                if (!std.mem.startsWith(u8, method_name, "on_")) {
                    continue;
                }

                self.scripting_behaviors.append(runtime.allocator, .{
                    .name = method_name[3..],
                    .method = methods[i],
                }) catch unreachable;
            }
        }
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
    pose_detector: engine.PoseDetector,
    allocator: std.mem.Allocator,

    wasm: engine.Wasm,
    native_behaviors: std.ArrayList(engine.Scripting.Type),
    scripting: engine.Scripting,
    objects: Slab(*GameObject),

    material: engine.Renderer.MaterialHandle,
    mesh: engine.Renderer.MeshHandle,
    chessboard: *GameObject,
    calibrated: bool,

    pub fn init(runtime: *Runtime, allocator: std.mem.Allocator) !void {
        runtime.allocator = allocator;

        runtime.gpu = engine.Gpu.init();
        runtime.window = engine.Window.init(&runtime.gpu, "simulo runtime");
        runtime.renderer = engine.Renderer.init(&runtime.gpu, &runtime.window);
        runtime.pose_detector = engine.PoseDetector.init();
        runtime.calibrated = false;

        runtime.native_behaviors = std.ArrayList(engine.Scripting.Type).init(runtime.allocator);
        runtime.scripting = engine.Scripting.init(runtime, allocator);
        const module = runtime.scripting.defineModule("simulo");

        _ = try runtime.scripting.defineClass(GameObject, module);
        runtime.wasm.zeroInit();
        runtime.scripting.defineMethod(GameObject, "__init__", GameObject.py__init__);
        runtime.scripting.defineProperty(GameObject, "x", GameObject.py_x);
        runtime.scripting.defineProperty(GameObject, "y", GameObject.py_y);
        runtime.scripting.defineMethod(GameObject, "set_position", GameObject.py_set_position);
        runtime.scripting.defineMethod(GameObject, "x_scale", GameObject.py_x_scale);
        runtime.scripting.defineMethod(GameObject, "y_scale", GameObject.py_y_scale);
        runtime.scripting.defineMethod(GameObject, "set_scale", GameObject.py_set_scale);
        runtime.scripting.defineMethod(GameObject, "delete", GameObject.py_delete);
        runtime.scripting.defineMethod(GameObject, "add_behavior", GameObject.py_add_behavior);

        try runtime.native_behaviors.append(try runtime.scripting.defineClass(behaviors.MovementBehavior, module));
        runtime.scripting.defineMethod(behaviors.MovementBehavior, "__init__", behaviors.MovementBehavior.py__init__);

        try runtime.native_behaviors.append(try runtime.scripting.defineClass(behaviors.LifetimeBehavior, module));
        runtime.scripting.defineMethod(behaviors.LifetimeBehavior, "__init__", behaviors.LifetimeBehavior.py__init__);

        runtime.objects = try Slab(*GameObject).init(runtime.allocator, 64);

        const image = createChessboard(&runtime.renderer);
        runtime.material = runtime.renderer.createUiMaterial(image, 1.0, 1.0, 1.0);
        runtime.mesh = runtime.renderer.createMesh(std.mem.asBytes(&vertices), &[_]u16{ 0, 1, 2, 2, 3, 0 });

        const chessboard = runtime.scripting.instantiate(GameObject);
        const chessboard_obj = runtime.scripting.getSelf(GameObject, chessboard).?;
        GameObject.init(runtime, chessboard_obj, 0, 0);
        runtime.scripting.defineVariable(module, "root_object", chessboard);
        runtime.chessboard = chessboard_obj;
    }

    pub fn deinit(self: *Runtime) void {
        self.wasm.deinit();
        self.scripting.deinit();
        self.objects.deinit();
        self.native_behaviors.deinit();

        self.pose_detector.stop();
        self.renderer.deinit();
        self.window.deinit();
        self.gpu.deinit();
    }

    pub fn runProgram(self: *Runtime, data: []const u8) !void {
        try self.wasm.init(data);
        const init_func = try self.wasm.getFunction("init");
        var args = [_]u32{0};
        _ = try self.wasm.callFunction(init_func, &args);
    }

    fn isNativeBehavior(self: *const Runtime, ty: engine.Scripting.Type) bool {
        for (self.native_behaviors.items) |behavior| {
            if (behavior == ty) {
                return true;
            }
        }
        return false;
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
            //const delta = now - last_time;
            last_time = now;

            const width: f32 = @floatFromInt(self.window.getWidth());
            const height: f32 = @floatFromInt(self.window.getHeight());

            self.chessboard.scale = if (self.calibrated) .{ 0, 0, 0 } else .{ width, height, 1 };
            self.renderer.setObjectTransform(self.chessboard.handle, self.chessboard.calculateTransform());

            const ui_projection = Mat4.ortho(width, height, -1.0, 1.0);
            _ = self.renderer.render(&ui_projection, &ui_projection);

            try self.processPoseDetections(width, height);

            //const deltaf: f32 = @floatFromInt(delta);
            //const event = events.UpdateEvent{ .delta = deltaf / 1000.0 };
            //for (self.objects.items()) |object| {
            //object.callEvent(self, &event);
            //}

            self.clearDeletedObjects();
        }
    }

    fn processPoseDetections(self: *Runtime, width: f32, height: f32) !void {
        while (self.pose_detector.nextEvent()) |event| {
            const detection = event.detection orelse {
                self.chessboard.callEvent(self, &events.PoseEvent{
                    .id = event.id,
                    .x = -1,
                    .y = -1,
                });
                continue;
            };

            const left_hand = detection.keypoints[9].pos;
            self.chessboard.callEvent(self, &events.PoseEvent{
                .id = event.id,
                .x = @floatCast(left_hand[0] * width),
                .y = @floatCast(left_hand[1] * height),
            });
            self.calibrated = true;
        }
    }

    fn clearDeletedObjects(_: *Runtime) void {
        // nop for now
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
