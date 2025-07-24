const std = @import("std");
const build_options = @import("build_options");

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

const wasm = @import("wasm/wasm.zig");
pub const Wasm = wasm.Wasm;
pub const WasmError = wasm.Error;

const inference = @import("inference/inference.zig");
pub const Inference = inference.Inference;
pub const Detection = inference.Detection;
pub const Keypoint = inference.Keypoint;

pub const Camera = @import("camera/camera.zig").Camera;
pub const Gpu = @import("gpu/gpu.zig").Gpu;

const loadImage = @import("image/image.zig").loadImage;

const behaviors = @import("behaviors.zig");
const events = @import("events.zig");

const Vertex = struct {
    position: @Vector(3, f32) align(16),
    tex_coord: @Vector(2, f32) align(8),
};

pub const GameObject = struct {
    pos: @Vector(3, f32),
    rotation: f32,
    scale: @Vector(3, f32),
    id: usize,
    handle: Renderer.ObjectHandle,
    native_behaviors: std.ArrayListUnmanaged(behaviors.Behavior),
    deleted: bool,
    internal: bool,

    pub fn init(runtime: *Runtime, id: usize, material: Renderer.MaterialHandle, x_: f32, y_: f32, internal: bool) error{OutOfMemory}!GameObject {
        const obj = GameObject{
            .pos = .{ x_, y_, 0 },
            .rotation = 0,
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
        const rotate = Mat4.rotateZ(self.rotation);
        const scale = Mat4.scale(.{ self.scale[0], self.scale[1], self.scale[2] });
        renderer.setObjectTransform(self.handle, translate.matmul(&rotate).matmul(&scale));
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
    images: std.ArrayList(Renderer.ImageHandle),
    pose_buffer: ?[*]f32,
    random: std.Random.Xoshiro256,
    outdated_object_transforms: util.IntSet(u32, 128),

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
        try Wasm.exposeFunction("simulo_set_object_material", wasmSetObjectMaterial);
        try Wasm.exposeFunction("simulo_set_object_position", wasmSetObjectPosition);
        try Wasm.exposeFunction("simulo_set_object_rotation", wasmSetObjectRotation);
        try Wasm.exposeFunction("simulo_set_object_scale", wasmSetObjectScale);
        try Wasm.exposeFunction("simulo_get_object_x", wasmGetObjectX);
        try Wasm.exposeFunction("simulo_get_object_y", wasmGetObjectY);
        try Wasm.exposeFunction("simulo_get_object_rotation", wasmGetObjectRotation);
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
        runtime.images = try std.ArrayList(Renderer.ImageHandle).initCapacity(runtime.allocator, 4);

        runtime.outdated_object_transforms = try util.IntSet(u32, 128).init(runtime.allocator, 64);
        errdefer runtime.outdated_object_transforms.deinit(runtime.allocator);

        errdefer runtime.images.deinit();
        runtime.pose_buffer = null;
        const now: u64 = @bitCast(std.time.microTimestamp());
        runtime.random = std.Random.Xoshiro256.init(now);

        runtime.masks = std.AutoHashMap(u64, MaskData).init(runtime.allocator);

        const image = createChessboard(&runtime.renderer);
        runtime.white_pixel_texture = runtime.renderer.createImage(&[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF }, 1, 1);
        const chessboard_material = try runtime.renderer.createUiMaterial(image, 1.0, 1.0, 1.0);
        runtime.mesh = try runtime.renderer.createMesh(std.mem.asBytes(&vertices), &[_]u16{ 0, 1, 2, 2, 3, 0 });

        runtime.mask_material = try runtime.renderer.createUiMaterial(image, 0.0, 0.0, 0.0);
        runtime.chessboard = runtime.createObject(0, 0, chessboard_material, true);
    }

    pub fn deinit(self: *Runtime) void {
        self.wasm.deinit() catch |err| {
            self.remote.log("wasm deinit failed: {any}", .{err});
        };
        self.masks.deinit();
        self.images.deinit();
        self.objects.deinit();
        self.outdated_object_transforms.deinit(self.allocator);
        self.object_ids.deinit();
        self.pose_detector.stop();
        self.renderer.deinit();
        self.window.deinit();
        self.gpu.deinit();
        self.remote.deinit();
    }

    fn runProgram(self: *Runtime, num_assets: usize) !void {
        self.wasm.deinit() catch |err| {
            self.remote.log("wasm deinit failed: {any}", .{err});
        };

        var i: usize = 0;
        while (i < self.objects.items.len) {
            const obj = &self.objects.items[i];
            if (!obj.internal) {
                self.deleteObject(obj.id);
            }
            i += 1;
        }

        // TODO: delete images
        self.images.clearRetainingCapacity();

        const local_path = build_options.wasm_path orelse "program.wasm";
        const data = try std.fs.cwd().readFileAlloc(self.allocator, local_path, std.math.maxInt(usize));
        defer self.allocator.free(data);

        var wasm_err: ?WasmError = null;
        self.wasm.init(self.allocator, @ptrCast(self), data, &wasm_err) catch |err_code| {
            self.remote.log("wasm initialization failed: {any}: {any}", .{ err_code, wasm_err });
            return error.WasmInitFailed;
        };

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

        for (0..num_assets) |asset_idx| {
            var image_path_buf: [16]u8 = undefined;
            const image_path = std.fmt.bufPrint(&image_path_buf, "asset_{d}.png", .{asset_idx}) catch unreachable;
            const image_data = std.fs.cwd().readFileAlloc(self.allocator, image_path, 10 * 1024 * 1024) catch |err| {
                self.remote.log("failed to read asset file at {s}: {s}", .{ image_path, @errorName(err) });
                return error.AssertReadFailed;
            };
            defer self.allocator.free(image_data);

            const image_info = loadImage(image_data) catch |err| {
                self.remote.log("failed to load data from {s}: {s}", .{ image_path, @errorName(err) });
                return error.AssertLoadFailed;
            };

            const image = self.renderer.createImage(image_info.data, image_info.width, image_info.height);
            self.images.append(image) catch |err| util.crash.oom(err);
        }
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

        var frame_count: usize = 0;
        var second_timer: i64 = std.time.milliTimestamp();

        while (self.window.poll()) {
            const now = std.time.milliTimestamp();
            const delta = now - last_time;
            last_time = now;

            frame_count += 1;
            if (now - second_timer >= 1000) {
                std.debug.print("fps: {d}\n", .{frame_count});
                frame_count = 0;
                second_timer = now;
            }

            const width: f32 = @floatFromInt(self.window.getWidth());
            const height: f32 = @floatFromInt(self.window.getHeight());

            const was_calibrated = self.calibrated;
            try self.processPoseDetections(width, height);

            if (self.getObject(self.chessboard)) |chessboard| {
                chessboard.scale = if (self.calibrated) .{ 0, 0, 0 } else .{ width, height, 1 };
                self.markOutdatedTransform(self.chessboard);
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

            self.recalculateOutdatedTransforms();

            const ui_projection = Mat4.ortho(width, height, -1.0, 1.0);
            self.renderer.render(&self.window, &ui_projection, &ui_projection) catch |err| {
                self.remote.log("render failed: {any}", .{err});
            };

            while (self.remote.nextMessage()) |msg| {
                var message = msg;
                defer message.deinit(self.allocator);

                switch (message) {
                    .download => |download| {
                        var should_run = true;

                        self.remote.fetch(download.program_url, &download.program_hash, "program.wasm") catch |err| {
                            self.remote.log("program download failed: {s}", .{@errorName(err)});
                            should_run = false;
                        };

                        for (download.assets, 0..) |asset, i| {
                            var dest_path_buf: [16]u8 = undefined;
                            const dest_path = std.fmt.bufPrint(&dest_path_buf, "asset_{d}.png", .{i}) catch unreachable;

                            self.remote.fetch(asset.url, &asset.hash, dest_path) catch |err| {
                                self.remote.log("asset download failed: {s}", .{@errorName(err)});
                                should_run = false;
                            };
                        }

                        if (should_run) {
                            try self.runProgram(download.assets.len);
                        }
                    },
                }
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
                _ = self.updateMaskObject(mask_data.left_id, lx, ly);
                _ = self.updateMaskObject(mask_data.right_id, rx, ry);
            } else {
                const left_id = self.updateMaskObject(null, lx, ly);
                const right_id = self.updateMaskObject(null, rx, ry);
                self.masks.put(event.id, .{ .left_id = left_id, .right_id = right_id }) catch |err| util.crash.oom(err);
            }
        } else {
            if (self.masks.get(event.id)) |mask_data| {
                self.deleteObject(mask_data.left_id);
                self.deleteObject(mask_data.right_id);
                std.debug.assert(self.masks.remove(event.id));
            }
        }
    }

    fn updateMaskObject(self: *Runtime, object_id: ?usize, x: f32, y: f32) usize {
        const spawn_x = x - MASK_WIDTH / 2.0;
        const spawn_y = y - MASK_HEIGHT / 3.0;

        if (object_id) |mask_obj_id| {
            const mask_obj = self.getObject(mask_obj_id).?;
            mask_obj.pos = .{ spawn_x, spawn_y, 0.0 };
            self.markOutdatedTransform(mask_obj_id);
            return mask_obj_id;
        }

        const obj_id = self.createObject(spawn_x, spawn_y, self.mask_material, true);
        const mask_obj = self.getObject(obj_id).?;
        mask_obj.scale = .{ MASK_WIDTH, MASK_HEIGHT, 1.0 };
        self.markOutdatedTransform(obj_id);
        return obj_id;
    }

    fn recalculateOutdatedTransforms(self: *Runtime) void {
        for (0..self.outdated_object_transforms.bucketCount()) |bucket| {
            for (self.outdated_object_transforms.bucketItems(bucket)) |obj_id| {
                const obj = self.getObject(obj_id).?;
                obj.recalculateTransform(&self.renderer);
            }
        }
        self.outdated_object_transforms.clear();
    }

    fn markOutdatedTransform(self: *Runtime, id: usize) void {
        self.outdated_object_transforms.put(self.allocator, @intCast(id)) catch |err| util.crash.oom(err);
    }

    fn wasmSetPoseBuffer(user_ptr: *anyopaque, buffer: [*]f32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        runtime.pose_buffer = buffer;
    }

    fn wasmCreateObject(user_ptr: *anyopaque, x: f32, y: f32, material_id: u32) u32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj_id = runtime.createObject(x, y, .{ .id = material_id }, false);
        return @intCast(obj_id);
    }

    fn createObject(self: *Runtime, x: f32, y: f32, material: Renderer.MaterialHandle, internal: bool) usize {
        const object_id, const object_index = self.object_ids.insert(std.math.maxInt(usize)) catch |err| {
            util.crash.oom(err);
        };

        const obj = GameObject.init(self, object_id, material, x, y, internal) catch |err| util.crash.oom(err);
        self.objects.append(obj) catch |err| util.crash.oom(err);

        const index = self.objects.items.len - 1;
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
        runtime.markOutdatedTransform(id);
    }

    fn wasmSetObjectRotation(user_ptr: *anyopaque, id: u32, rotation: f32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.getObject(id) orelse {
            runtime.remote.log("tried to set rotation of non-existent object {x}", .{id});
            return;
        };
        obj.rotation = rotation;
        runtime.markOutdatedTransform(id);
    }

    fn wasmSetObjectScale(user_ptr: *anyopaque, id: u32, x: f32, y: f32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.getObject(id) orelse {
            runtime.remote.log("tried to set scale of non-existent object {x}", .{id});
            return;
        };
        obj.scale = .{ x, y, 1 };
        runtime.markOutdatedTransform(id);
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

    fn wasmGetObjectRotation(user_ptr: *anyopaque, id: u32) f32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.getObject(id) orelse {
            runtime.remote.log("tried to get rotation of non-existent object {x}", .{id});
            return 0.0;
        };
        return obj.rotation;
    }

    fn wasmDeleteObject(user_ptr: *anyopaque, id: u32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        runtime.deleteObject(id);
    }

    fn wasmSetObjectMaterial(user_ptr: *anyopaque, id: u32, material_id: u32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.getObject(id) orelse {
            runtime.remote.log("tried to set material of non-existent object {x}", .{id});
            return;
        };
        runtime.renderer.setObjectMaterial(obj.handle, .{ .id = material_id }) catch |err| util.crash.oom(err);
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

    fn wasmCreateMaterial(user_ptr: *anyopaque, image_id: u32, r: f32, g: f32, b: f32) u32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const image = if (image_id == std.math.maxInt(u32)) runtime.white_pixel_texture else runtime.images.items[image_id];
        const material = runtime.renderer.createUiMaterial(image, r, g, b) catch |err| util.crash.oom(err);
        return material.id;
    }
};

pub fn createChessboard(renderer: *Renderer) Renderer.ImageHandle {
    const width = 1280;
    const height = 800;
    const square = 160;
    const radius: i32 = square / 2;
    const radius_sq = radius * radius;
    const cols = width / square;
    const rows = height / square;

    var checkerboard: [width * height * 4]u8 = undefined;
    @memset(&checkerboard, 0);

    for (0..width) |x| {
        for (0..height) |y| {
            var white = false;
            const x_square = x / square;
            const y_square = y / square;
            if (x_square % 2 == y_square % 2) {
                white = true;

                const local_x: i32 = @intCast(x % square);
                const local_y: i32 = @intCast(y % square);

                const top = y_square == 0;
                const bottom = y_square == rows - 1;
                const left = x_square == 0;
                const right = x_square == cols - 1;

                if (top and local_y < radius) {
                    if (local_x < radius) {
                        const dx = radius - local_x;
                        const dy = radius - local_y;
                        if (dx * dx + dy * dy > radius_sq) white = false;
                    } else if (local_x >= square - radius) {
                        const dx = local_x - (square - radius);
                        const dy = radius - local_y;
                        if (dx * dx + dy * dy > radius_sq) white = false;
                    }
                }

                if (bottom and local_y >= square - radius) {
                    if (local_x < radius) {
                        const dx = radius - local_x;
                        const dy = local_y - (square - radius);
                        if (dx * dx + dy * dy > radius_sq) white = false;
                    } else if (local_x >= square - radius) {
                        const dx = local_x - (square - radius);
                        const dy = local_y - (square - radius);
                        if (dx * dx + dy * dy > radius_sq) white = false;
                    }
                }

                if (left and local_x < radius and !top and local_y < radius) {
                    const dx = radius - local_x;
                    const dy = radius - local_y;
                    if (dx * dx + dy * dy > radius_sq) white = false;
                } else if (left and local_x < radius and !bottom and local_y >= square - radius) {
                    const dx = radius - local_x;
                    const dy = local_y - (square - radius);
                    if (dx * dx + dy * dy > radius_sq) white = false;
                }

                if (right and local_x >= square - radius and !top and local_y < radius) {
                    const dx = local_x - (square - radius);
                    const dy = radius - local_y;
                    if (dx * dx + dy * dy > radius_sq) white = false;
                } else if (right and local_x >= square - radius and !bottom and local_y >= square - radius) {
                    const dx = local_x - (square - radius);
                    const dy = local_y - (square - radius);
                    if (dx * dx + dy * dy > radius_sq) white = false;
                }
            }

            if (white) {
                checkerboard[(y * width + x) * 4 + 0] = 0xFF;
                checkerboard[(y * width + x) * 4 + 1] = 0xFF;
                checkerboard[(y * width + x) * 4 + 2] = 0xFF;
            }
            checkerboard[(y * width + x) * 4 + 3] = 0xFF;
        }
    }
    return renderer.createImage(&checkerboard, width, height);
}
