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

const Vertex = struct {
    position: @Vector(3, f32) align(16),
    tex_coord: @Vector(2, f32) align(8),
};

pub const GameObject = struct {
    pos: @Vector(3, f32),
    scale: @Vector(3, f32),
    id: usize,
    handle: Renderer.ObjectHandle,
    native_behaviors: std.ArrayListUnmanaged(behaviors.Behavior),
    deleted: bool,

    pub fn init(runtime: *Runtime, id: usize, material: Renderer.MaterialHandle, x_: f32, y_: f32) GameObject {
        const obj = GameObject{
            .pos = .{ x_, y_, 0 },
            .scale = .{ 1, 1, 1 },
            .id = id,
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
    init_func: ?Wasm.Function,
    update_func: ?Wasm.Function,
    pose_func: ?Wasm.Function,
    objects: std.ArrayList(GameObject),
    object_ids: Slab(usize),
    random: std.Random.Xoshiro256,

    white_pixel_texture: Renderer.ImageHandle,
    mesh: Renderer.MeshHandle,
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
        try Wasm.exposeFunction("simulo_random", wasmRandom);
        try Wasm.exposeFunction("simulo_window_width", wasmWindowWidth);
        try Wasm.exposeFunction("simulo_window_height", wasmWindowHeight);
        try Wasm.exposeFunction("simulo_create_material", wasmCreateMaterial);
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
        runtime.init_func = null;
        runtime.update_func = null;
        runtime.pose_func = null;
        runtime.objects = try std.ArrayList(GameObject).initCapacity(runtime.allocator, 64);
        errdefer runtime.objects.deinit();
        runtime.object_ids = try Slab(usize).init(runtime.allocator, 64);
        errdefer runtime.object_ids.deinit();

        const now: u64 = @bitCast(std.time.microTimestamp());
        runtime.random = std.Random.Xoshiro256.init(now);

        const image = createChessboard(&runtime.renderer);
        runtime.white_pixel_texture = runtime.renderer.createImage(&[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF }, 1, 1);
        const chessboard_material = runtime.renderer.createUiMaterial(image, 1.0, 1.0, 1.0);
        runtime.mesh = runtime.renderer.createMesh(std.mem.asBytes(&vertices), &[_]u16{ 0, 1, 2, 2, 3, 0 });

        try runtime.objects.append(GameObject.init(runtime, std.math.maxInt(usize), chessboard_material, 0, 0));
    }

    pub fn deinit(self: *Runtime) void {
        self.wasm.deinit();
        self.objects.deinit();
        self.object_ids.deinit();
        self.pose_detector.stop();
        self.renderer.deinit();
        self.window.deinit();
        self.gpu.deinit();
        self.remote.deinit();
    }

    fn runProgram(self: *Runtime, program_url: []const u8) !void {
        self.wasm.deinit();

        for (self.objects.items[1..]) |*obj| {
            self.renderer.deleteObject(obj.handle);
        }
        self.objects.resize(1) catch |err| {
            self.remote.log("impossible: error downsizing objects to 1: {any}", .{err});
            return;
        };
        self.object_ids.deinit();
        self.object_ids = try Slab(usize).init(self.allocator, 64);

        self.remote.fetchProgram(program_url) catch |err| {
            self.remote.log("program download failed- attempting to use last downloaded program ({any})", .{err});
        };

        const data = try std.fs.cwd().readFileAlloc(self.allocator, "program.wasm", std.math.maxInt(usize));
        defer self.allocator.free(data);

        try self.wasm.init(@ptrCast(self), data);
        self.init_func = self.wasm.getFunction("init") orelse {
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

            const was_calibrated = self.calibrated;
            try self.processPoseDetections(width, height);

            const chessboard = &self.objects.items[0];
            chessboard.scale = if (self.calibrated) .{ 0, 0, 0 } else .{ width, height, 1 };
            chessboard.recalculateTransform(&self.renderer);

            if (self.calibrated) {
                if (!was_calibrated) {
                    if (self.init_func) |init_func| {
                        _ = self.wasm.callFunction(init_func, .{}) catch unreachable;
                    }
                }

                const deltaf: f32 = @floatFromInt(delta);
                if (self.update_func) |func| {
                    _ = self.wasm.callFunction(func, .{deltaf / 1000}) catch unreachable;
                }
            }

            const ui_projection = Mat4.ortho(width, height, -1.0, 1.0);
            self.renderer.render(&self.window, &ui_projection, &ui_projection) catch |err| {
                self.remote.log("render failed: {any}", .{err});
            };

            if (self.remote.nextMessage()) |message| {
                const url = message.buf[0..message.used];
                self.remote.log("Downloading program from {s}", .{url});
                try self.runProgram(url);
            }
        }
    }

    fn processPoseDetections(self: *Runtime, width: f32, height: f32) !void {
        const was_calibrated = self.calibrated;
        const pose_func = self.pose_func orelse return;

        while (self.pose_detector.nextEvent()) |event| {
            self.calibrated = true;

            if (!was_calibrated) {
                continue;
            }

            const id_u32: u32 = @intCast(event.id);
            const detection = event.detection orelse {
                _ = self.wasm.callFunction(pose_func, .{ id_u32, @as(f32, -1), @as(f32, -1) }) catch unreachable;
                continue;
            };

            const left_hand = detection.keypoints[9].pos;
            _ = self.wasm.callFunction(pose_func, .{
                id_u32,
                left_hand[0] * width,
                left_hand[1] * height,
            }) catch unreachable;
        }
    }

    fn wasmCreateObject(user_ptr: *anyopaque, x: f32, y: f32, material_id: u32) u32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));

        // For redundancy, allocate an object index in the set *before* creating the object.
        // If creating the object fails, the index will be freed. Otherwise, the index will be later
        // used to store the object's ID.
        const object_id, const object_index = runtime.object_ids.insert(std.math.maxInt(usize)) catch {
            runtime.remote.log("failed to reserve object set index", .{});
            return 0;
        };

        const material = Renderer.MaterialHandle{ .id = material_id };
        runtime.objects.append(GameObject.init(runtime, object_id, material, x, y)) catch |err| {
            runtime.remote.log("failed to create object: {any}", .{err});
            runtime.object_ids.delete(object_id) catch |err2| {
                runtime.remote.log("impossible: object id not deleted: {any}", .{err2});
            };
            return 0;
        };
        const index = runtime.objects.items.len - 1;
        runtime.objects.items[index].recalculateTransform(&runtime.renderer);
        object_index.* = index;

        return @intCast(object_id);
    }

    fn getObject(self: *Runtime, id: usize) ?*GameObject {
        const object_index = self.object_ids.get(id) orelse return null;
        if (object_index.* >= self.objects.items.len) return null;
        return &self.objects.items[object_index.*];
    }

    fn wasmSetObjectPosition(user_ptr: *anyopaque, id: u32, x: f32, y: f32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.getObject(id) orelse {
            runtime.remote.log("tried to set position of non-existent object {x}", .{id});
            return;
        };
        obj.pos = .{ x, y, 0 };
        obj.recalculateTransform(&runtime.renderer);
    }

    fn wasmSetObjectScale(user_ptr: *anyopaque, id: u32, x: f32, y: f32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.getObject(id) orelse {
            runtime.remote.log("tried to set scale of non-existent object {x}", .{id});
            return;
        };
        obj.scale = .{ x, y, 1 };
        obj.recalculateTransform(&runtime.renderer);
    }

    fn wasmGetObjectX(user_ptr: *anyopaque, id: u32) f32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.getObject(id) orelse {
            runtime.remote.log("tried to get x position of non-existent object {x}", .{id});
            return 0.0;
        };
        return obj.pos[0];
    }

    fn wasmGetObjectY(user_ptr: *anyopaque, id: u32) f32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.getObject(id) orelse {
            runtime.remote.log("tried to get y position of non-existent object {x}", .{id});
            return 0.0;
        };
        return obj.pos[1];
    }

    fn wasmDeleteObject(user_ptr: *anyopaque, id: u32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const object_index = runtime.object_ids.get(id) orelse {
            runtime.remote.log("tried to delete non-existent object {x}", .{id});
            return;
        };

        if (object_index.* >= runtime.objects.items.len) {
            runtime.remote.log(
                "object index {any} was out of bounds {any} for id {any}",
                .{ object_index.*, runtime.objects.items.len, id },
            );
            return;
        }

        // Perform swap-removal. If the object is at the end, simply remove it. Otherwise, swap it
        // with the last one and update the object ID's target index.
        var obj: GameObject = undefined;
        if (object_index.* == runtime.objects.items.len - 1) {
            obj = runtime.objects.pop().?;
        } else {
            obj = runtime.objects.items[object_index.*];
            const new_object = runtime.objects.pop().?;
            const new_object_index = runtime.object_ids.get(new_object.id) orelse {
                runtime.remote.log("impossible: couldn't find object index for replacement id {d}", .{new_object.id});
                return;
            };
            new_object_index.* = object_index.*;
            runtime.objects.items[object_index.*] = new_object;
        }

        runtime.object_ids.delete(id) catch |err| {
            runtime.remote.log("impossible: couldn't delete existing object id {d}: {any}", .{ id, err });
        };

        runtime.renderer.deleteObject(obj.handle);
    }

    fn wasmRandom(user_ptr: *anyopaque) f32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        return runtime.random.random().float(f32);
    }

    fn wasmWindowWidth(user_ptr: *anyopaque) i32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        return runtime.window.getWidth();
    }

    fn wasmWindowHeight(user_ptr: *anyopaque) i32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        return runtime.window.getHeight();
    }

    fn wasmCreateMaterial(user_ptr: *anyopaque, r: f32, g: f32, b: f32) u32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const material = runtime.renderer.createUiMaterial(runtime.white_pixel_texture, r, g, b);
        return material.id;
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
            }
            checkerboard[(y * 1280 + x) * 4 + 3] = 0xFF;
        }
    }
    return renderer.createImage(&checkerboard, 1280, 800);
}
