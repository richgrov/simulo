const std = @import("std");

const engine = @import("engine");
const reflect = engine.utils.reflect;
const Mat4 = engine.math.Mat4;
const Slab = engine.utils.Slab;

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

pub const GameObject = struct {
    pos: @Vector(3, f32),
    scale: @Vector(3, f32),
    handle: engine.Renderer.ObjectHandle,
    native_behaviors: std.ArrayListUnmanaged(behaviors.Behavior),
    deleted: bool,

    pub fn init(runtime: *Runtime, x_: f32, y_: f32) GameObject {
        const obj = GameObject{
            .pos = .{ x_, y_, 0 },
            .scale = .{ 5, 5, 1 },
            .handle = runtime.renderer.addObject(runtime.mesh, Mat4.identity(), runtime.material),
            .native_behaviors = .{},
            .deleted = false,
        };
        runtime.renderer.setObjectTransform(obj.handle, obj.calculateTransform());
        return obj;
    }

    pub fn callEvent(self: *GameObject, runtime: *Runtime, event: anytype) void {
        const EventType = @TypeOf(event);

        const struct_type = switch (@typeInfo(EventType)) {
            .pointer => |ptr| reflect.typeId(ptr.child),
            else => @compileError("event must be a pointer to a struct"),
        };

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

    pub fn calculateTransform(self: *const GameObject) Mat4 {
        const translate = Mat4.translate(.{ self.pos[0], self.pos[1], self.pos[2] });
        const scale = Mat4.scale(.{ self.scale[0], self.scale[1], self.scale[2] });
        return translate.matmul(&scale);
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
    objects: Slab(GameObject),

    material: engine.Renderer.MaterialHandle,
    mesh: engine.Renderer.MeshHandle,
    chessboard: usize,
    calibrated: bool,

    pub fn globalInit() !void {
        try engine.Wasm.globalInit();
        errdefer engine.Wasm.globalDeinit();
        try engine.Wasm.exposeFunction("simulo_create_object", wasmCreateObject);
        try engine.Wasm.exposeFunction("simulo_set_object_position", wasmSetObjectPosition);
        try engine.Wasm.exposeFunction("simulo_set_object_scale", wasmSetObjectScale);
    }

    pub fn globalDeinit() void {
        engine.Wasm.globalDeinit();
    }

    pub fn init(runtime: *Runtime, allocator: std.mem.Allocator) !void {
        runtime.allocator = allocator;

        runtime.gpu = engine.Gpu.init();
        runtime.window = engine.Window.init(&runtime.gpu, "simulo runtime");
        runtime.renderer = engine.Renderer.init(&runtime.gpu, &runtime.window);
        runtime.pose_detector = engine.PoseDetector.init();
        runtime.calibrated = false;

        runtime.objects = try Slab(GameObject).init(runtime.allocator, 64);

        const image = createChessboard(&runtime.renderer);
        runtime.material = runtime.renderer.createUiMaterial(image, 1.0, 1.0, 1.0);
        runtime.mesh = runtime.renderer.createMesh(std.mem.asBytes(&vertices), &[_]u16{ 0, 1, 2, 2, 3, 0 });

        runtime.chessboard = try runtime.objects.insert(GameObject.init(runtime, 0, 0));
    }

    pub fn deinit(self: *Runtime) void {
        self.wasm.deinit();
        self.pose_detector.stop();
        self.renderer.deinit();
        self.window.deinit();
        self.gpu.deinit();
    }

    pub fn runProgram(self: *Runtime, data: []const u8) !void {
        try self.wasm.init(@ptrCast(self), data);
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

    pub fn run(self: *Runtime) !void {
        try self.pose_detector.start();
        var last_time = std.time.milliTimestamp();

        while (self.window.poll()) {
            const now = std.time.milliTimestamp();
            //const delta = now - last_time;
            last_time = now;

            const width: f32 = @floatFromInt(self.window.getWidth());
            const height: f32 = @floatFromInt(self.window.getHeight());

            const chessboard = try self.objects.get(self.chessboard);
            chessboard.scale = if (self.calibrated) .{ 0, 0, 0 } else .{ width, height, 1 };
            self.renderer.setObjectTransform(chessboard.handle, chessboard.calculateTransform());

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
        _ = width;
        _ = height;
        while (self.pose_detector.nextEvent()) |event| {
            const detection = event.detection orelse {
                //self.chessboard.callEvent(self, &events.PoseEvent{
                //    .id = event.id,
                //    .x = -1,
                //    .y = -1,
                //});
                continue;
            };

            const left_hand = detection.keypoints[9].pos;
            _ = left_hand;
            //self.chessboard.callEvent(self, &events.PoseEvent{
            //    .id = event.id,
            //    .x = @floatCast(left_hand[0] * width),
            //    .y = @floatCast(left_hand[1] * height),
            //});
            self.calibrated = true;
        }
    }

    fn clearDeletedObjects(_: *Runtime) void {
        // nop for now
    }

    fn wasmCreateObject(user_ptr: *anyopaque, x: f32, y: f32) u32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const id = runtime.objects.insert(GameObject.init(runtime, x, y)) catch unreachable;
        const obj = runtime.objects.get(id) catch unreachable;
        obj.scale = .{ 500, 500, 500 };
        runtime.renderer.setObjectTransform(obj.handle, obj.calculateTransform());
        return @intCast(id);
    }

    fn wasmSetObjectPosition(user_ptr: *anyopaque, id: u32, x: f32, y: f32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.objects.get(id) catch return;
        obj.pos = .{ x, y, 0 };
        runtime.renderer.setObjectTransform(obj.handle, obj.calculateTransform());
    }

    fn wasmSetObjectScale(user_ptr: *anyopaque, id: u32, x: f32, y: f32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.objects.get(id) catch return;
        obj.scale = .{ x, y, 1 };
        runtime.renderer.setObjectTransform(obj.handle, obj.calculateTransform());
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
