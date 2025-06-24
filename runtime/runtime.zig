const std = @import("std");

const engine = @import("engine");
const Mat4 = engine.math.Mat4;

const util = @import("util");
const reflect = util.reflect;
const Slab = util.Slab;

const pose = @import("inference/pose.zig");
pub const PoseDetector = pose.PoseDetector;

pub const Remote = @import("remote/remote.zig").Remote;

pub const Renderer = @import("render/renderer.zig").Renderer;
pub const Window = @import("window/window.zig").Window;

pub const Wasm = @import("wasm/wasm.zig").Wasm;

const inference = @import("inference/inference.zig");
pub const Inference = inference.Inference;
pub const Detection = inference.Detection;
pub const Keypoint = inference.Keypoint;

pub const Camera = @import("camera/camera.zig").Camera;
pub const Gpu = @import("gpu/gpu.zig").Gpu;

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
    pos: @Vector(3, f32),
    scale: @Vector(3, f32),
    handle: Renderer.ObjectHandle,
    native_behaviors: std.ArrayListUnmanaged(behaviors.Behavior),
    deleted: bool,

    pub fn init(runtime: *Runtime, material: Renderer.MaterialHandle, x_: f32, y_: f32) GameObject {
        const obj = GameObject{
            .pos = .{ x_, y_, 0 },
            .scale = .{ 1, 1, 1 },
            .handle = runtime.renderer.addObject(runtime.mesh, Mat4.identity(), material),
            .native_behaviors = .{},
            .deleted = false,
        };
        obj.recalculateTransform(&runtime.renderer);
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

    pub fn recalculateTransform(self: *const GameObject, renderer: *Renderer) void {
        const translate = Mat4.translate(.{ self.pos[0], self.pos[1], self.pos[2] });
        const scale = Mat4.scale(.{ self.scale[0], self.scale[1], self.scale[2] });
        renderer.setObjectTransform(self.handle, translate.matmul(&scale));
    }
};

const vertices = [_]Vertex{
    .{ .position = .{ 0.0, 0.0, 0.0 }, .tex_coord = .{ 0.0, 0.0 } },
    .{ .position = .{ 1.0, 0.0, 0.0 }, .tex_coord = .{ 1.0, 0.0 } },
    .{ .position = .{ 1.0, 1.0, 0.0 }, .tex_coord = .{ 1.0, 1.0 } },
    .{ .position = .{ 0.0, 1.0, 0.0 }, .tex_coord = .{ 0.0, 1.0 } },
};

pub const Runtime = struct {
    gpu: Gpu,
    window: Window,
    renderer: Renderer,
    pose_detector: PoseDetector,
    remote: Remote,
    allocator: std.mem.Allocator,

    wasm: Wasm,
    update_func: Wasm.Function,
    pose_func: Wasm.Function,
    objects: Slab(GameObject),

    blank_material: Renderer.MaterialHandle,
    mesh: Renderer.MeshHandle,
    chessboard: usize,
    calibrated: bool,

    pub fn globalInit() !void {
        try Wasm.globalInit();
        errdefer Wasm.globalDeinit();
        try Wasm.exposeFunction("simulo_create_object", wasmCreateObject);
        try Wasm.exposeFunction("simulo_set_object_position", wasmSetObjectPosition);
        try Wasm.exposeFunction("simulo_set_object_scale", wasmSetObjectScale);
        try Wasm.exposeFunction("simulo_get_object_x", wasmGetObjectX);
        try Wasm.exposeFunction("simulo_get_object_y", wasmGetObjectY);
        try Wasm.exposeFunction("simulo_delete_object", wasmDeleteObject);
    }

    pub fn globalDeinit() void {
        Wasm.globalDeinit();
    }

    pub fn init(runtime: *Runtime, machine_id: []const u8, private_key: *const [32]u8, allocator: std.mem.Allocator) !void {
        runtime.allocator = allocator;
        runtime.remote = try Remote.init(allocator, machine_id, private_key);
        errdefer runtime.remote.deinit();
        try runtime.remote.start();

        runtime.gpu = Gpu.init();
        runtime.window = Window.init(&runtime.gpu, "simulo runtime");
        runtime.renderer = Renderer.init(&runtime.gpu, &runtime.window);
        runtime.pose_detector = PoseDetector.init();
        runtime.calibrated = false;

        runtime.wasm.zeroInit();
        runtime.objects = try Slab(GameObject).init(runtime.allocator, 64);
        errdefer runtime.objects.deinit();

        const image = createChessboard(&runtime.renderer);
        const white_pixel = runtime.renderer.createImage(&[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF }, 1, 1);
        const chessboard_material = runtime.renderer.createUiMaterial(image, 1.0, 1.0, 1.0);
        runtime.blank_material = runtime.renderer.createUiMaterial(white_pixel, 1.0, 1.0, 1.0);
        runtime.mesh = runtime.renderer.createMesh(std.mem.asBytes(&vertices), &[_]u16{ 0, 1, 2, 2, 3, 0 });

        runtime.chessboard, _ = try runtime.objects.insert(GameObject.init(runtime, chessboard_material, 0, 0));
    }

    pub fn deinit(self: *Runtime) void {
        self.wasm.deinit();
        self.objects.deinit();
        self.pose_detector.stop();
        self.renderer.deinit();
        self.window.deinit();
        self.gpu.deinit();
        self.remote.deinit();
    }

    pub fn runProgram(self: *Runtime, program_url: []const u8) !void {
        self.remote.fetchProgram(program_url) catch |err| {
            self.remote.log("program download failed- attempting to use last downloaded program ({any})", .{err});
        };

        const data = try std.fs.cwd().readFileAlloc(self.allocator, "program.wasm", std.math.maxInt(usize));
        defer self.allocator.free(data);

        try self.wasm.init(@ptrCast(self), data);
        const init_func = self.wasm.getFunction("init") orelse {
            self.remote.log("program missing init function", .{});
            return error.MissingInitFunction;
        };
        self.update_func = self.wasm.getFunction("update") orelse {
            self.remote.log("program missing update function", .{});
            return error.MissingUpdateFunction;
        };
        self.pose_func = self.wasm.getFunction("pose") orelse {
            self.remote.log("program missing pose function", .{});
            return error.MissingPoseFunction;
        };

        _ = try self.wasm.callFunction(init_func, .{});
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
            const delta = now - last_time;
            last_time = now;

            const width: f32 = @floatFromInt(self.window.getWidth());
            const height: f32 = @floatFromInt(self.window.getHeight());

            if (self.objects.get(self.chessboard)) |chessboard| {
                chessboard.scale = if (self.calibrated) .{ 0, 0, 0 } else .{ width, height, 1 };
                chessboard.recalculateTransform(&self.renderer);
            }

            const deltaf: f32 = @floatFromInt(delta);
            _ = self.wasm.callFunction(self.update_func, .{deltaf / 1000}) catch unreachable;

            const ui_projection = Mat4.ortho(width, height, -1.0, 1.0);
            _ = self.renderer.render(&ui_projection, &ui_projection);

            try self.processPoseDetections(width, height);
        }
    }

    fn processPoseDetections(self: *Runtime, width: f32, height: f32) !void {
        while (self.pose_detector.nextEvent()) |event| {
            const id_u32: u32 = @intCast(event.id);
            const detection = event.detection orelse {
                _ = self.wasm.callFunction(self.pose_func, .{ id_u32, @as(f32, -1), @as(f32, -1) }) catch unreachable;
                continue;
            };

            const left_hand = detection.keypoints[9].pos;
            _ = self.wasm.callFunction(self.pose_func, .{
                id_u32,
                left_hand[0] * width,
                left_hand[1] * height,
            }) catch unreachable;
            self.calibrated = true;
        }
    }

    fn wasmCreateObject(user_ptr: *anyopaque, x: f32, y: f32) u32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const id, const obj = runtime.objects.insert(GameObject.init(runtime, runtime.blank_material, x, y)) catch unreachable;
        obj.recalculateTransform(&runtime.renderer);
        return @intCast(id);
    }

    fn wasmSetObjectPosition(user_ptr: *anyopaque, id: u32, x: f32, y: f32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.objects.get(id) orelse {
            runtime.remote.log("tried to set position of non-existent object {x}", .{id});
            return;
        };
        obj.pos = .{ x, y, 0 };
        obj.recalculateTransform(&runtime.renderer);
    }

    fn wasmSetObjectScale(user_ptr: *anyopaque, id: u32, x: f32, y: f32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.objects.get(id) orelse {
            runtime.remote.log("tried to set scale of non-existent object {x}", .{id});
            return;
        };
        obj.scale = .{ x, y, 1 };
        obj.recalculateTransform(&runtime.renderer);
    }

    fn wasmGetObjectX(user_ptr: *anyopaque, id: u32) f32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.objects.get(id) orelse {
            runtime.remote.log("tried to get x position of non-existent object {x}", .{id});
            return 0.0;
        };
        return obj.pos[0];
    }

    fn wasmGetObjectY(user_ptr: *anyopaque, id: u32) f32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.objects.get(id) orelse {
            runtime.remote.log("tried to get y position of non-existent object {x}", .{id});
            return 0.0;
        };
        return obj.pos[1];
    }

    fn wasmDeleteObject(user_ptr: *anyopaque, id: u32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.objects.get(id) orelse {
            runtime.remote.log("tried to delete non-existent object {x}", .{id});
            return;
        };
        runtime.renderer.deleteObject(obj.handle);
        runtime.objects.delete(id) catch {
            runtime.remote.log("impossible: deinitialized but failed to delete object {x}", .{id});
        };
    }
};

pub fn createChessboard(renderer: *Renderer) Renderer.ImageHandle {
    var checkerboard: [1280 * 800 * 4]u8 = undefined;
    @memset(&checkerboard, 0);
    for (0..1280) |x| {
        for (0..800) |y| {
            const x_square = x / 160;
            const y_square = y / 160;
            if (x_square % 2 == y_square % 2) {
                checkerboard[(y * 1280 + x) * 4 + 0] = 0xFF;
                checkerboard[(y * 1280 + x) * 4 + 1] = 0xFF;
                checkerboard[(y * 1280 + x) * 4 + 2] = 0xFF;
                checkerboard[(y * 1280 + x) * 4 + 3] = 0xFF;
            }
        }
    }
    return renderer.createImage(&checkerboard, 1280, 800);
}
