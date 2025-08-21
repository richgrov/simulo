const std = @import("std");
const build_options = @import("build_options");

const engine = @import("engine");
const Mat4 = engine.math.Mat4;

const util = @import("util");
const reflect = util.reflect;
const Slab = util.Slab;

const fs_storage = @import("fs_storage.zig");

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

const EyeGuard = @import("eyeguard.zig").EyeGuard;

const Vertex = struct {
    position: @Vector(3, f32) align(16),
    tex_coord: @Vector(2, f32) align(8),
};

pub const GameObject = struct {
    id: usize,
    handle: Renderer.ObjectHandle,
    deleted: bool,

    children: ?util.IntSet(usize, 64),
    parent: ?usize,
    wasm_this: i32,

    pub fn init(runtime: *Runtime, material: Renderer.MaterialHandle, parent: ?usize) error{OutOfMemory}!GameObject {
        return .{
            .id = undefined,
            .handle = try runtime.renderer.addObject(runtime.mesh, Mat4.identity(), material, 0),
            .deleted = false,
            .children = null,
            .parent = parent,
            .wasm_this = undefined,
        };
    }

    pub fn addChild(self: *GameObject, runtime: *Runtime, child: usize) void {
        if (self.children) |*children| {
            children.put(runtime.allocator, child) catch |err| util.crash.oom(err);
        } else {
            var children = util.IntSet(usize, 64).init(runtime.allocator, 1) catch |err| util.crash.oom(err);
            children.put(runtime.allocator, child) catch |err| util.crash.oom(err);
            self.children = children;
        }

        const child_obj = runtime.objects.get(child) orelse {
            runtime.remote.log("tried to add non-existent child {d} to object {d}", .{ child, self.id });
            return;
        };
        child_obj.parent = self.id;
    }

    pub fn deinit(self: *GameObject, runtime: *Runtime) void {
        if (self.deleted) {
            return;
        }

        if (self.children) |*children| {
            children.deinit(runtime.allocator);
        }

        self.deleted = true;
        runtime.renderer.deleteObject(self.handle);
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
    last_window_width: i32,
    last_window_height: i32,
    renderer: Renderer,
    pose_detector: PoseDetector,
    remote: Remote,
    allocator: std.mem.Allocator,

    wasm: Wasm,
    wasm_funcs: ?struct {
        init: Wasm.Function,
        update: Wasm.Function,
        recalculate_transform: Wasm.Function,
        pose: Wasm.Function,
        drop: Wasm.Function,
    },
    wasm_pose_buffer: ?[*]f32,
    wasm_transform_buffer: ?[*]f32,
    objects: Slab(GameObject),
    isolated_objects: util.IntSet(usize, 16),
    root_object: ?usize,
    images: std.ArrayList(Renderer.ImageHandle),
    random: std.Random.Xoshiro256,
    outdated_object_transforms: util.IntSet(u32, 128),
    last_ping: i64,

    white_pixel_texture: Renderer.ImageHandle,
    chessboard: Renderer.ObjectHandle,
    mesh: Renderer.MeshHandle,
    calibrated: bool,
    eyeguard: EyeGuard,

    pub fn globalInit() !void {
        try Wasm.globalInit();
        errdefer Wasm.globalDeinit();
        try Wasm.exposeFunction("simulo_set_root", wasmSetRoot);
        try Wasm.exposeFunction("simulo_set_buffers", wasmSetBuffers);
        try Wasm.exposeFunction("simulo_create_object", wasmCreateObject);
        try Wasm.exposeFunction("simulo_add_object_child", wasmAddObjectChild);
        try Wasm.exposeFunction("simulo_get_children", wasmGetChildren);
        try Wasm.exposeFunction("simulo_set_object_ptrs", wasmSetObjectPtrs);
        try Wasm.exposeFunction("simulo_set_object_material", wasmSetObjectMaterial);
        try Wasm.exposeFunction("simulo_mark_transform_outdated", wasmMarkTransformOutdated);
        try Wasm.exposeFunction("simulo_remove_object_from_parent", wasmRemoveObjectFromParent);
        try Wasm.exposeFunction("simulo_drop_object", wasmDropObject);
        try Wasm.exposeFunction("simulo_random", wasmRandom);
        try Wasm.exposeFunction("simulo_window_width", wasmWindowWidth);
        try Wasm.exposeFunction("simulo_window_height", wasmWindowHeight);
        try Wasm.exposeFunction("simulo_create_material", wasmCreateMaterial);
        try Wasm.exposeFunction("simulo_delete_material", wasmDeleteMaterial);
        try Wasm.exposeFunction("simulo_unref_material", wasmUnrefMaterial);
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
        runtime.last_window_width = 0;
        runtime.last_window_height = 0;
        runtime.renderer = try Renderer.init(&runtime.gpu, &runtime.window, allocator);
        errdefer runtime.renderer.deinit();
        runtime.pose_detector = PoseDetector.init();
        errdefer runtime.pose_detector.stop();
        runtime.calibrated = false;

        runtime.wasm.zeroInit();
        runtime.wasm_funcs = null;
        runtime.wasm_pose_buffer = null;
        runtime.wasm_transform_buffer = null;
        runtime.objects = try Slab(GameObject).init(runtime.allocator, 64);
        errdefer runtime.objects.deinit();

        runtime.isolated_objects = try util.IntSet(usize, 16).init(runtime.allocator, 1);
        errdefer runtime.isolated_objects.deinit(runtime.allocator);

        runtime.root_object = null;

        runtime.images = try std.ArrayList(Renderer.ImageHandle).initCapacity(runtime.allocator, 4);

        runtime.outdated_object_transforms = try util.IntSet(u32, 128).init(runtime.allocator, 64);
        errdefer runtime.outdated_object_transforms.deinit(runtime.allocator);

        runtime.last_ping = std.time.milliTimestamp();

        errdefer runtime.images.deinit();
        const now: u64 = @bitCast(std.time.microTimestamp());
        runtime.random = std.Random.Xoshiro256.init(now);

        const image = createChessboard(&runtime.renderer);
        runtime.white_pixel_texture = runtime.renderer.createImage(&[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF }, 1, 1);
        const chessboard_material = try runtime.renderer.createUiMaterial(image, 1.0, 1.0, 1.0);
        runtime.mesh = try runtime.renderer.createMesh(std.mem.asBytes(&vertices), &[_]u16{ 0, 1, 2, 2, 3, 0 });
        runtime.eyeguard = try EyeGuard.init(runtime.allocator, &runtime.renderer, runtime.mesh, runtime.white_pixel_texture);
        errdefer runtime.eyeguard.deinit();

        runtime.chessboard = try runtime.renderer.addObject(runtime.mesh, Mat4.identity(), chessboard_material, 1);
        errdefer runtime.renderer.deleteObject(runtime.chessboard);
    }

    pub fn deinit(self: *Runtime) void {
        self.wasm.deinit() catch |err| {
            self.remote.log("wasm deinit failed: {any}", .{err});
        };
        self.eyeguard.deinit();
        self.images.deinit();

        if (self.root_object) |id| {
            self.deinitObject(id);
        }

        for (0..self.isolated_objects.bucketCount()) |bucket| {
            for (self.isolated_objects.bucketItems(bucket)) |id| {
                self.deinitObject(id);
            }
        }
        self.isolated_objects.deinit(self.allocator);

        self.objects.deinit();
        self.outdated_object_transforms.deinit(self.allocator);
        self.pose_detector.stop();
        self.renderer.deinit();
        self.window.deinit();
        self.gpu.deinit();
        self.remote.deinit();
    }

    fn runProgram(self: *Runtime, program_hash: *const [32]u8, asset_hashes: []const [32]u8) !void {
        self.wasm.deinit() catch |err| {
            self.remote.log("wasm deinit failed: {any}", .{err});
        };

        if (self.root_object) |id| {
            self.deinitObject(id);
            self.root_object = null;
        }

        for (0..self.isolated_objects.bucketCount()) |bucket| {
            for (self.isolated_objects.bucketItems(bucket)) |id| {
                self.deinitObject(id);
            }
        }
        self.isolated_objects.clear();

        // TODO: delete images
        self.images.clearRetainingCapacity();

        var local_path_buf: [1024]u8 = undefined;
        const local_path = build_options.wasm_path orelse (fs_storage.getCachePath(&local_path_buf, program_hash) catch unreachable);
        const data = try std.fs.cwd().readFileAlloc(self.allocator, local_path, std.math.maxInt(usize));
        defer self.allocator.free(data);

        var wasm_err: ?WasmError = null;
        self.wasm.init(self.allocator, @ptrCast(self), data, &wasm_err) catch |err_code| {
            self.remote.log("wasm initialization failed: {s}: {any}", .{ @errorName(err_code), wasm_err });
            return error.WasmInitFailed;
        };

        const init_func = self.wasm.getFunction("simulo__start") orelse {
            self.remote.log("program missing init function", .{});
            return error.MissingFunction;
        };

        self.wasm_funcs = .{
            .init = init_func,
            .update = self.wasm.getFunction("simulo__update") orelse {
                self.remote.log("program missing update function", .{});
                return error.MissingFunction;
            },
            .recalculate_transform = self.wasm.getFunction("simulo__recalculate_transform") orelse {
                self.remote.log("program missing recalculate_transform function", .{});
                return error.MissingFunction;
            },
            .pose = self.wasm.getFunction("simulo__pose") orelse {
                self.remote.log("program missing pose function", .{});
                return error.MissingFunction;
            },
            .drop = self.wasm.getFunction("simulo__drop") orelse {
                self.remote.log("program missing drop function", .{});
                return error.MissingFunction;
            },
        };
        self.wasm_pose_buffer = null;
        self.wasm_transform_buffer = null;

        for (asset_hashes) |asset_hash| {
            var image_path_buf: [1024]u8 = undefined;
            const image_path = fs_storage.getCachePath(&image_path_buf, &asset_hash) catch unreachable;
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

        if (self.calibrated) {
            _ = self.wasm.callFunction(init_func, .{}) catch unreachable;

            if (self.wasm_pose_buffer == null or self.wasm_transform_buffer == null) {
                return error.BuffersNotInitialized;
            }
        }
    }

    fn deinitObject(self: *Runtime, id: usize) void {
        const obj = self.objects.get(id).?;

        if (obj.children) |*children| {
            for (0..children.bucketCount()) |bucket| {
                for (children.bucketItems(bucket)) |child_id| {
                    self.deinitObject(child_id);
                }
            }
        }

        obj.deinit(self);
        self.objects.delete(id) catch {
            self.remote.log("tried to delete non-existent object {d}", .{id});
        };
    }

    fn tryRunLatestProgram(self: *Runtime) void {
        const program_info = fs_storage.loadLatestProgram() catch |err| {
            self.remote.log("failed to load latest program: {s}", .{@errorName(err)});
            return;
        };

        if (program_info) |info| {
            self.runProgram(&info.program_hash, info.asset_hashes.items()) catch |err| {
                self.remote.log("failed to run latest program: {s}", .{@errorName(err)});
            };
        }
    }

    pub fn run(self: *Runtime) !void {
        if (build_options.wasm_path) |_| {
            self.runProgram(undefined, &[_][32]u8{}) catch unreachable;
        } else {
            self.tryRunLatestProgram();
        }

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

            const width = self.window.getWidth();
            const height = self.window.getHeight();

            if (width != self.last_window_width or height != self.last_window_height) {
                self.last_window_width = width;
                self.last_window_height = height;

                if (comptime util.vulkan) {
                    self.renderer.handleResize(width, height, self.window.surface());
                }

                self.renderer.setObjectTransform(self.chessboard, if (self.calibrated) Mat4.zero() else Mat4.scale(.{ @floatFromInt(width), @floatFromInt(height), 1 }));
            }

            try self.processPoseDetections();

            if (self.calibrated) {
                const deltaf: f32 = @floatFromInt(delta);
                if (self.root_object) |id| {
                    self.updateObject(id, deltaf / 1000);
                }
            }

            self.recalculateOutdatedTransforms();

            const ui_projection = Mat4.ortho(
                @floatFromInt(self.last_window_width),
                @floatFromInt(self.last_window_height),
                -1.0,
                1.0,
            );
            self.renderer.render(&self.window, &ui_projection, &ui_projection) catch |err| {
                self.remote.log("render failed: {any}", .{err});
            };

            if (now - self.last_ping >= 1000 * 30) {
                self.last_ping = now;
                self.remote.sendPing();
            }

            while (self.remote.nextMessage()) |msg| {
                var message = msg;
                defer message.deinit(self.allocator);

                switch (message) {
                    .download => |download| {
                        var should_run = true;

                        var program_path_buf: [1024]u8 = undefined;
                        const program_path = fs_storage.getCachePath(&program_path_buf, &download.program_hash) catch unreachable;

                        self.remote.fetch(download.program_url, &download.program_hash, program_path) catch |err| {
                            self.remote.log("program download failed: {s}", .{@errorName(err)});
                            should_run = false;
                        };

                        for (download.assets) |asset| {
                            var dest_path_buf: [1024]u8 = undefined;
                            const dest_path = fs_storage.getCachePath(&dest_path_buf, &asset.hash) catch unreachable;

                            self.remote.fetch(asset.url, &asset.hash, dest_path) catch |err| {
                                self.remote.log("asset download failed: {s}", .{@errorName(err)});
                                should_run = false;
                            };
                        }

                        var asset_hashes = util.FixedArrayList([32]u8, 64).init();
                        for (download.assets) |asset| {
                            try asset_hashes.append(asset.hash);
                        }

                        fs_storage.storeLatestProgram(&download.program_hash, asset_hashes.items()) catch |err| {
                            self.remote.log("failed to store latest info: {s}", .{@errorName(err)});
                        };

                        if (should_run) {
                            try self.runProgram(&download.program_hash, asset_hashes.items());
                        }
                    },
                }
            }
        }
    }

    fn updateObject(self: *Runtime, id: usize, delta: f32) void {
        const obj = self.objects.get(id) orelse return;
        _ = self.wasm.callFunction(self.wasm_funcs.?.update, .{ obj.wasm_this, delta }) catch unreachable;

        if (obj.children) |*children| {
            for (0..children.bucketCount()) |bucket| {
                for (children.bucketItems(bucket)) |child_id| {
                    self.updateObject(child_id, delta);
                }
            }
        }
    }

    fn processPoseDetections(self: *Runtime) !void {
        const width: f32 = @floatFromInt(self.last_window_width);
        const height: f32 = @floatFromInt(self.last_window_height);

        while (self.pose_detector.nextEvent()) |event| {
            switch (event) {
                .calibrated => {
                    self.calibrated = true;

                    if (self.wasm_pose_buffer == null) {
                        if (self.wasm_funcs) |funcs| {
                            _ = self.wasm.callFunction(funcs.init, .{@as(u32, 0)}) catch unreachable;

                            if (self.wasm_pose_buffer == null or self.wasm_transform_buffer == null) {
                                return error.BuffersNotInitialized;
                            }
                        }
                    }

                    self.renderer.setObjectTransform(self.chessboard, Mat4.zero());
                },
                .move => |move| {
                    self.eyeguard.handleEvent(move.id, &move.detection, &self.renderer, width, height);

                    const funcs = self.wasm_funcs orelse return;
                    const pose_buffer = self.wasm_pose_buffer orelse return;

                    const id_u32: u32 = @intCast(move.id);

                    for (move.detection.keypoints, 0..) |kp, i| {
                        pose_buffer[i * 2] = kp.pos[0] * width;
                        pose_buffer[i * 2 + 1] = kp.pos[1] * height;
                    }

                    _ = self.wasm.callFunction(funcs.pose, .{ id_u32, true }) catch unreachable;
                },
                .lost => |id| {
                    self.eyeguard.handleDelete(&self.renderer, id);

                    const funcs = self.wasm_funcs orelse return;

                    const id_u32: u32 = @intCast(id);
                    _ = self.wasm.callFunction(funcs.pose, .{ id_u32, false }) catch unreachable;
                },
                .profile => |profile_logs| {
                    _ = profile_logs;
                },
                .fault => |fault| {
                    self.remote.log("pose detector fault: {s}: {any}", .{ @tagName(fault.category), fault.err });
                },
            }
        }
    }

    fn recalculateOutdatedTransforms(self: *Runtime) void {
        for (0..self.outdated_object_transforms.bucketCount()) |bucket| {
            for (self.outdated_object_transforms.bucketItems(bucket)) |obj_id| {
                const obj = self.objects.get(obj_id).?;
                _ = self.wasm.callFunction(self.wasm_funcs.?.recalculate_transform, .{obj.wasm_this}) catch unreachable;
                const col_array = self.wasm_transform_buffer.?;
                const transform = Mat4.fromColumnMajorPtr(col_array);
                self.renderer.setObjectTransform(obj.handle, transform);
            }
        }
        self.outdated_object_transforms.clear();
    }

    pub fn markOutdatedTransform(self: *Runtime, id: usize) void {
        self.outdated_object_transforms.put(self.allocator, @intCast(id)) catch |err| util.crash.oom(err);
    }

    fn wasmSetRoot(user_ptr: *anyopaque, id: u32, this: i32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.objects.get(id) orelse {
            runtime.remote.log("tried to set root of non-existent object {d}", .{id});
            return;
        };

        obj.wasm_this = this;
        runtime.root_object = id;
        std.debug.assert(runtime.isolated_objects.delete(@intCast(id)));
    }

    fn wasmSetBuffers(user_ptr: *anyopaque, pose_buffer: [*]f32, transform_buffer: [*]f32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        runtime.wasm_pose_buffer = pose_buffer;
        runtime.wasm_transform_buffer = transform_buffer;
    }

    fn wasmCreateObject(user_ptr: *anyopaque, material_id: u32) u32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj_id = runtime.createObject(.{ .id = material_id });
        runtime.isolated_objects.put(runtime.allocator, obj_id) catch |err| util.crash.oom(err);
        return @intCast(obj_id);
    }

    fn wasmAddObjectChild(user_ptr: *anyopaque, parent: u32, child: u32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const parent_obj = runtime.objects.get(parent) orelse {
            runtime.remote.log("tried to add non-existent child {d} to object {d}", .{ child, parent });
            return;
        };
        parent_obj.addChild(runtime, child);
        std.debug.assert(runtime.isolated_objects.delete(@intCast(child)));
    }

    fn wasmGetChildren(user_ptr: *anyopaque, id: u32, out_children: [*]i32, count: u32) u32 {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.objects.get(id) orelse {
            runtime.remote.log("tried to get children of non-existent object {d}", .{id});
            return 0;
        };

        var i: usize = 0;
        if (obj.children) |*children| {
            outer: for (0..children.bucketCount()) |bucket| {
                for (children.bucketItems(bucket)) |child_id| {
                    if (i >= count) {
                        break :outer;
                    }

                    out_children[i] = runtime.objects.get(child_id).?.wasm_this;
                    i += 1;
                }
            }
        }

        return @intCast(i);
    }

    fn wasmSetObjectPtrs(user_ptr: *anyopaque, id: u32, this: i32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.objects.get(id) orelse {
            runtime.remote.log("tried to set object ptr of non-existent object {d}", .{id});
            return;
        };

        obj.wasm_this = this;
    }

    pub fn createObject(self: *Runtime, material: Renderer.MaterialHandle) usize {
        const obj = GameObject.init(self, material, null) catch |err| util.crash.oom(err);
        const object_id, const obj_ptr = self.objects.insert(obj) catch |err| util.crash.oom(err);
        obj_ptr.*.id = object_id;
        return object_id;
    }

    pub fn deleteObject(self: *Runtime, id: usize) void {
        self.objects.delete(id) catch {
            self.remote.log("tried to delete non-existent object {d}", .{id});
            return;
        };

        _ = self.outdated_object_transforms.delete(@intCast(id));
        _ = self.isolated_objects.delete(@intCast(id));
    }

    fn deleteMaterial(self: *Runtime, id: u32) void {
        const material_handle = Renderer.MaterialHandle{ .id = id };
        self.renderer.deleteMaterial(material_handle);
    }

    fn unrefMaterial(self: *Runtime, mat_id: u32) void {
        self.renderer.unrefMaterial(mat_id);
    }

    fn wasmRemoveObjectFromParent(user_ptr: *anyopaque, id: u32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.objects.get(id) orelse {
            runtime.remote.log("tried to remove non-existent object {d}", .{id});
            return;
        };

        if (obj.parent) |parent| {
            const parent_obj = runtime.objects.get(parent) orelse {
                runtime.remote.log("tried to delete from non-existent parent {d} of object {d}", .{ parent, obj.id });
                return;
            };
            std.debug.assert(parent_obj.children.?.delete(obj.id));
            runtime.deleteChildren(id);
        }
    }

    fn deleteChildren(self: *Runtime, id: usize) void {
        const obj = self.objects.get(id) orelse {
            self.remote.log("tried to delete children of non-existent object {d}", .{id});
            return;
        };

        if (obj.children) |*children| {
            for (0..children.bucketCount()) |bucket| {
                for (children.bucketItems(bucket)) |child_id| {
                    self.deleteChildren(child_id);
                }
            }
        }

        obj.deinit(self);
        _ = self.wasm.callFunction(self.wasm_funcs.?.drop, .{obj.wasm_this}) catch unreachable;
    }

    fn wasmDropObject(user_ptr: *anyopaque, id: u32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        runtime.deleteObject(id);
    }

    fn wasmDeleteMaterial(user_ptr: *anyopaque, id: u32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        runtime.deleteMaterial(id);
    }

    fn wasmUnrefMaterial(user_ptr: *anyopaque, mat_id: u32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        runtime.unrefMaterial(mat_id);
    }

    fn wasmSetObjectMaterial(user_ptr: *anyopaque, id: u32, material_id: u32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        const obj = runtime.objects.get(id) orelse {
            runtime.remote.log("tried to set material of non-existent object {d}", .{id});
            return;
        };
        runtime.renderer.setObjectMaterial(obj.handle, .{ .id = material_id }) catch |err| util.crash.oom(err);
    }

    fn wasmMarkTransformOutdated(user_ptr: *anyopaque, id: u32) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_ptr));
        runtime.markOutdatedTransform(@intCast(id));
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
