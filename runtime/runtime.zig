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
    internal: bool,

    pub fn init(runtime: *Runtime, id: usize, material: Renderer.MaterialHandle, x_: f32, y_: f32, internal: bool) !GameObject {
        const obj = GameObject{
            .pos = .{ x_, y_, 0 },
            .scale = .{ 1, 1, 1 },
            .id = id,
            .handle = try runtime.renderer.addObject(runtime.mesh, Mat4.identity(), material, if (internal) 1 else 0),
            .native_behaviors = .{},
            .deleted = false,
            .internal = internal,
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

const MASK_WIDTH = 100.0;
const MASK_HEIGHT = 50.0;

const MaskData = struct {
    left_id: usize,
    right_id: usize,
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
    pose_buffer: ?[*]f32,
    random: std.Random.Xoshiro256,

    white_pixel_texture: Renderer.ImageHandle,
    chessboard: usize,
    mesh: Renderer.MeshHandle,
    mask_material: Renderer.MaterialHandle,
    masks: std.AutoHashMap(u64, MaskData),
    calibrated: bool,

    pub fn globalInit() !void {
        try Wasm.globalInit();
        errdefer Wasm.globalDeinit();
        try Wasm.exposeFunction("simulo_set_pose_buffer", wasmSetPoseBuffer);
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
        errdefer runtime.gpu.deinit();
        runtime.window = Window.init(&runtime.gpu, "simulo runtime");
        errdefer runtime.window.deinit();
        runtime.renderer = try Renderer.init(&runtime.gpu, &runtime.window, allocator);
        errdefer runtime.renderer.deinit();
        runtime.pose_detector = PoseDetector.init();
        errdefer runtime.pose_detector.stop();
        runtime.calibrated = false;

        runtime.wasm.zeroInit();
        runtime.init_func = null;
        runtime.update_func = null;
        runtime.pose_func = null;
        runtime.objects = try std.ArrayList(GameObject).initCapacity(runtime.allocator, 64);
        errdefer runtime.objects.deinit();
        runtime.object_ids = try Slab(usize).init(runtime.allocator, 64);
        errdefer runtime.object_ids.deinit();
        runtime.pose_buffer = null;
        const now: u64 = @bitCast(std.time.microTimestamp());
        runtime.random = std.Random.Xoshiro256.init(now);

        runtime.masks = std.AutoHashMap(u64, MaskData).init(runtime.allocator);

        const image = createChessboard(&runtime.renderer);
        runtime.white_pixel_texture = runtime.renderer.createImage(&[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF }, 1, 1);
        const chessboard_material = try runtime.renderer.createUiMaterial(image, 1.0, 1.0, 1.0);
        runtime.mesh = try runtime.renderer.createMesh(std.mem.asBytes(&vertices), &[_]u16{ 0, 1, 2, 2, 3, 0 });

        runtime.mask_material = try runtime.renderer.createUiMaterial(image, 0.0, 0.0, 0.0);
        runtime.chessboard = try runtime.createObject(0, 0, chessboard_material, true);
    }

    pub fn deinit(self: *Runtime) void {
        self.wasm.deinit();
        self.masks.deinit();
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

        var i: usize = 0;
        while (i < self.objects.items.len) {
            const obj = &self.objects.items[i];
            if (!obj.internal) {
                self.deleteObject(obj.id);
            }
            i += 1;
        }

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

            if (self.getObject(self.chessboard)) |chessboard| {
                chessboard.scale = if (self.calibrated) .{ 0, 0, 0 } else .{ width, height, 1 };
                chessboard.recalculateTransform(&self.renderer);
            }

            if (self.calibrated) {
                if (!was_calibrated) {
                    if (self.init_func) |init_func| {
                        _ = self.wasm.callFunction(init_func, .{@as(u32, 0)}) catch unreachable;

                        if (self.pose_buffer == null) {
                            return error.PoseBufferNotInitialized;
                        }
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

        while (self.pose_detector.nextEvent()) |event| {
            self.calibrated = true;

            self.updateMask(&event, width, height);

            if (!was_calibrated) {
                continue;
            }

            const pose_func = self.pose_func orelse return;
            const pose_buffer = self.pose_buffer orelse return;

            const id_u32: u32 = @intCast(event.id);
            const detection = event.detection orelse {
                _ = self.wasm.callFunction(pose_func, .{ id_u32, false }) catch unreachable;
                continue;
            };

            for (detection.keypoints, 0..) |kp, i| {
                pose_buffer[i * 2] = kp.pos[0] * width;
                pose_buffer[i * 2 + 1] = kp.pos[1] * height;
            }

            _ = self.wasm.callFunction(pose_func, .{ id_u32, true }) catch unreachable;
        }
    }

    fn updateMask(self: *Runtime, event: *const pose.PoseEvent, window_width: f32, window_height: f32) void {
        if (event.detection) |det| {
            const l_eye = det.keypoints[1];
            const r_eye = det.keypoints[2];
            const lx = l_eye.pos[0] * window_width;
            const ly = l_eye.pos[1] * window_height;
            const rx = r_eye.pos[0] * window_width;
            const ry = r_eye.pos[1] * window_height;

            if (self.masks.get(event.id)) |mask_data| {
                _ = self.updateMaskObject(mask_data.left_id, lx, ly) catch |err| {
                    self.remote.log("failed to update left mask: {any}", .{err});
                };
                _ = self.updateMaskObject(mask_data.right_id, rx, ry) catch |err| {
                    self.remote.log("failed to update right mask: {any}", .{err});
                };
            } else {
                const left_id = self.updateMaskObject(null, lx, ly) catch |err| cat: {
                    self.remote.log("failed to create left mask: {any}", .{err});
                    break :cat std.math.maxInt(usize);
                };
                const right_id = self.updateMaskObject(null, rx, ry) catch |err| cat: {
                    self.remote.log("failed to create right mask: {any}", .{err});
                    break :cat std.math.maxInt(usize);
                };
                self.masks.put(event.id, .{ .left_id = left_id, .right_id = right_id }) catch |err| {
                    self.remote.log("failed to track mask object: {any}", .{err});
                    return;
                };
            }
        } else {
            if (self.masks.get(event.id)) |mask_data| {
                self.deleteObject(mask_data.left_id);
                self.deleteObject(mask_data.right_id);
            }
        }
    }

    fn updateMaskObject(self: *Runtime, object_id: ?usize, x: f32, y: f32) !usize {
        const spawn_x = x - MASK_WIDTH / 2.0;
        const spawn_y = y - MASK_HEIGHT / 3.0;

        if (object_id) |mask_obj_id| {
            const mask_obj = self.getObject(mask_obj_id) orelse return error.MaskNotFound;
            mask_obj.pos = .{ spawn_x, spawn_y, 0.0 };
            mask_obj.recalculateTransform(&self.renderer);
            return mask_obj_id;
        }

        const obj_id = try self.createObject(spawn_x, spawn_y, self.mask_material, true);
        const mask_obj = self.getObject(obj_id) orelse return error.CreatedMaskNotFound;
        mask_obj.scale = .{ MASK_WIDTH, MASK_HEIGHT, 1.0 };
        mask_obj.recalculateTransform(&self.renderer);
        return obj_id;
    }

    fn wasmSetPoseBuffer(user_ptr: *anyopaque, buffer: [*]f32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        runtime.pose_buffer = buffer;
    }

    fn wasmCreateObject(user_ptr: *anyopaque, x: f32, y: f32, material_id: u32) u32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj_id = runtime.createObject(x, y, .{ .id = material_id }, false) catch |err| {
            std.log.err("Failed to create object: {}", .{err});
            return 0;
        };
        return @intCast(obj_id);
    }

    fn createObject(self: *Runtime, x: f32, y: f32, material: Renderer.MaterialHandle, internal: bool) !usize {
        // For redundancy, allocate an object index in the set *before* creating the object.
        // If creating the object fails, the index will be freed. Otherwise, the index will be later
        // used to store the object's ID.
        const object_id, const object_index = self.object_ids.insert(std.math.maxInt(usize)) catch {
            return error.ReserveObjectIndexFailed;
        };

        var obj = try GameObject.init(self, object_id, material, x, y, internal);
        errdefer obj.delete(self);
        self.objects.append(obj) catch { // todo handle failure
            self.object_ids.delete(object_id) catch {
                return error.ObjectCreateRecoveryFailed;
            };
            return error.ObjectCreateFailed;
        };
        const index = self.objects.items.len - 1;
        self.objects.items[index].recalculateTransform(&self.renderer);
        object_index.* = index;

        return object_id;
    }

    fn getObject(self: *Runtime, id: usize) ?*GameObject {
        const object_index = self.object_ids.get(id) orelse return null;
        if (object_index.* >= self.objects.items.len) return null;
        return &self.objects.items[object_index.*];
    }

    fn deleteObject(self: *Runtime, id: usize) void {
        const object_index = self.object_ids.get(id) orelse {
            self.remote.log("tried to delete non-existent object {x}", .{id});
            return;
        };

        if (object_index.* >= self.objects.items.len) {
            self.remote.log(
                "object index {any} was out of bounds {any} for id {any}",
                .{ object_index.*, self.objects.items.len, id },
            );
            return;
        }

        // Perform swap-removal. If the object is at the end, simply remove it. Otherwise, swap it
        // with the last one and update the object ID's target index.
        var obj: GameObject = undefined;
        if (object_index.* == self.objects.items.len - 1) {
            obj = self.objects.pop().?;
        } else {
            obj = self.objects.items[object_index.*];
            const new_object = self.objects.pop().?;
            const new_object_index = self.object_ids.get(new_object.id) orelse {
                self.remote.log("impossible: couldn't find object index for replacement id {d}", .{new_object.id});
                return;
            };
            new_object_index.* = object_index.*;
            self.objects.items[object_index.*] = new_object;
        }

        self.object_ids.delete(id) catch |err| {
            self.remote.log("impossible: couldn't delete existing object id {d}: {any}", .{ id, err });
        };

        obj.delete(self);
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
        runtime.deleteObject(id);
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
        const material = runtime.renderer.createUiMaterial(runtime.white_pixel_texture, r, g, b) catch |err| {
            runtime.remote.log("failed to create material: {any}", .{err});
            return std.math.maxInt(u32);
        };
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
