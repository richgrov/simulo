const std = @import("std");
const build_options = @import("build_options");

const engine = @import("engine");
const Mat4 = engine.math.Mat4;

const util = @import("util");
const reflect = util.reflect;

const fs_storage = @import("fs_storage.zig");

const pose = @import("inference/pose.zig");
pub const PoseDetector = pose.PoseDetector;

pub const Remote = if (build_options.cloud)
    @import("remote/remote.zig").Remote
else
    @import("remote/noop_remote.zig").NoOpRemote;

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
    scene: engine.Scene,
    assets: std.StringHashMap(?Renderer.ImageHandle),
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
        try Wasm.exposeFunction("simulo_num_children", wasmNumChildren);
        try Wasm.exposeFunction("simulo_get_children", wasmGetChildren);
        try Wasm.exposeFunction("simulo_set_object_ptrs", wasmSetObjectPtrs);
        try Wasm.exposeFunction("simulo_mark_transform_outdated", wasmMarkTransformOutdated);
        try Wasm.exposeFunction("simulo_remove_object_from_parent", wasmRemoveObjectFromParent);
        try Wasm.exposeFunction("simulo_drop_object", wasmDropObject);

        try Wasm.exposeFunction("simulo_create_rendered_object", wasmCreateRenderedObject);
        try Wasm.exposeFunction("simulo_set_rendered_object_material", wasmSetRenderedObjectMaterial);
        try Wasm.exposeFunction("simulo_set_rendered_object_transform", wasmSetRenderedObjectTransform);
        try Wasm.exposeFunction("simulo_drop_rendered_object", wasmDropRenderedObject);

        try Wasm.exposeFunction("simulo_random", wasmRandom);
        try Wasm.exposeFunction("simulo_window_width", wasmWindowWidth);
        try Wasm.exposeFunction("simulo_window_height", wasmWindowHeight);

        try Wasm.exposeFunction("simulo_create_material", wasmCreateMaterial);
        try Wasm.exposeFunction("simulo_update_material", wasmUpdateMaterial);
        try Wasm.exposeFunction("simulo_drop_material", wasmDropMaterial);
    }

    pub fn globalDeinit() void {
        Wasm.globalDeinit();
    }

    pub fn init(runtime: *Runtime, allocator: std.mem.Allocator) !void {
        runtime.allocator = allocator;
        runtime.remote = try Remote.init(allocator);
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
        runtime.scene = try engine.Scene.init(runtime.allocator);
        errdefer runtime.scene.deinit();

        runtime.assets = std.StringHashMap(?Renderer.ImageHandle).init(runtime.allocator);
        errdefer runtime.assets.deinit();

        runtime.outdated_object_transforms = try util.IntSet(u32, 128).init(runtime.allocator, 64);
        errdefer runtime.outdated_object_transforms.deinit(runtime.allocator);

        runtime.last_ping = std.time.milliTimestamp();

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
            std.log.err("wasm deinit failed: {any}", .{err});
        };
        self.eyeguard.deinit();

        var assets_keys = self.assets.keyIterator();
        while (assets_keys.next()) |key| {
            self.allocator.free(key.*);
        }
        self.assets.deinit();

        self.scene.deinit();

        self.outdated_object_transforms.deinit(self.allocator);
        self.pose_detector.stop();
        self.renderer.deinit();
        self.window.deinit();
        self.gpu.deinit();
        self.remote.deinit();
    }

    fn runProgram(self: *Runtime, program_hash: *const [32]u8, assets: []const fs_storage.ProgramAsset) !void {
        self.wasm.deinit() catch |err| {
            std.log.err("wasm deinit failed: {any}", .{err});
        };

        self.scene.deinit();
        self.scene = try engine.Scene.init(self.allocator);

        var assets_keys = self.assets.iterator();
        while (assets_keys.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            // TODO: delete image if present
        }
        self.assets.clearRetainingCapacity();

        var local_path_buf: [1024]u8 = undefined;
        const local_path = build_options.wasm_path orelse (fs_storage.getCachePath(&local_path_buf, program_hash) catch unreachable);
        const data = try std.fs.cwd().readFileAlloc(self.allocator, local_path, std.math.maxInt(usize));
        defer self.allocator.free(data);

        var wasm_err: ?WasmError = null;
        self.wasm.init(self.allocator, data, &wasm_err) catch |err_code| {
            std.log.err("wasm initialization failed: {s}: {any}", .{ @errorName(err_code), wasm_err });
            return error.WasmInitFailed;
        };

        const init_func = self.wasm.getFunction("simulo_main") orelse {
            std.log.err("program missing init function", .{});
            return error.MissingFunction;
        };

        self.wasm_funcs = .{
            .init = init_func,
            .update = self.wasm.getFunction("simulo__update") orelse {
                std.log.err("program missing update function", .{});
                return error.MissingFunction;
            },
            .recalculate_transform = self.wasm.getFunction("simulo__recalculate_transform") orelse {
                std.log.err("program missing recalculate_transform function", .{});
                return error.MissingFunction;
            },
            .pose = self.wasm.getFunction("simulo__pose") orelse {
                std.log.err("program missing pose function", .{});
                return error.MissingFunction;
            },
            .drop = self.wasm.getFunction("simulo__drop") orelse {
                std.log.err("program missing drop function", .{});
                return error.MissingFunction;
            },
        };
        self.wasm_pose_buffer = null;
        self.wasm_transform_buffer = null;

        for (assets) |*asset| {
            var image_path_buf: [1024]u8 = undefined;
            const image_path = fs_storage.getCachePath(&image_path_buf, &asset.hash) catch unreachable;
            const image_data = std.fs.cwd().readFileAlloc(self.allocator, image_path, 10 * 1024 * 1024) catch |err| {
                std.log.err("failed to read asset file at {s}: {s}", .{ image_path, @errorName(err) });
                return error.AssertReadFailed;
            };
            defer self.allocator.free(image_data);

            const image_info = loadImage(image_data) catch |err| {
                std.log.err("failed to load data from {s}: {s}", .{ image_path, @errorName(err) });
                return error.AssertLoadFailed;
            };

            const image = self.renderer.createImage(image_info.data, image_info.width, image_info.height);

            const name = self.allocator.dupe(u8, asset.name.?.items()) catch |err| util.crash.oom(err);
            self.assets.put(name, image) catch |err| util.crash.oom(err);
        }

        if (self.calibrated) {
            _ = self.wasm.callFunction(init_func, .{}) catch unreachable;

            if (self.wasm_pose_buffer == null or self.wasm_transform_buffer == null) {
                return error.BuffersNotInitialized;
            }
        }
    }

    fn tryRunLatestProgram(self: *Runtime) void {
        const program_info = fs_storage.loadLatestProgram() catch |err| {
            std.log.err("failed to load latest program: {s}", .{@errorName(err)});
            return;
        };

        if (program_info) |info| {
            self.runProgram(&info.program_hash, info.assets.items()) catch |err| {
                std.log.err("failed to run latest program: {s}", .{@errorName(err)});
            };
        }
    }

    pub fn run(self: *Runtime) !void {
        if (build_options.wasm_path) |_| {
            self.runProgram(undefined, &[_]fs_storage.ProgramAsset{}) catch unreachable;
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
                if (self.scene.root_object) |root_id| {
                    const deltaf: f32 = @floatFromInt(delta);
                    const Updater = struct {
                        const Data = struct { runtime: *Runtime, delta: f32 };
                        fn update(user_data: Data, _: u32, obj: *engine.Object) void {
                            _ = user_data.runtime.wasm.callFunction(user_data.runtime.wasm_funcs.?.update, .{ obj.this, user_data.delta }) catch unreachable;
                        }
                    };
                    self.scene.dfs(root_id, Updater.Data, .{ .runtime = self, .delta = deltaf / 1000 }, Updater.update) catch unreachable;
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
                std.log.err("render failed: {any}", .{err});
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
                            std.log.err("program download failed: {s}", .{@errorName(err)});
                            should_run = false;
                        };

                        for (download.files) |file| {
                            var dest_path_buf: [1024]u8 = undefined;
                            const dest_path = fs_storage.getCachePath(&dest_path_buf, &file.asset.hash) catch unreachable;

                            self.remote.fetch(file.url, &file.asset.hash, dest_path) catch |err| {
                                std.log.err("asset download failed: {s}", .{@errorName(err)});
                                should_run = false;
                            };
                        }

                        var assets = util.FixedArrayList(fs_storage.ProgramAsset, 64).init();
                        for (download.files) |file| {
                            try assets.append(file.asset);
                        }

                        fs_storage.storeLatestProgram(&download.program_hash, assets.items()) catch |err| {
                            std.log.err("failed to store latest info: {s}", .{@errorName(err)});
                        };

                        if (should_run) {
                            try self.runProgram(&download.program_hash, assets.items());
                        }
                    },
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
                    std.log.err("pose detector fault: {s}: {any}", .{ @tagName(fault.category), fault.err });
                },
            }
        }
    }

    fn recalculateOutdatedTransforms(self: *Runtime) void {
        for (0..self.outdated_object_transforms.bucketCount()) |bucket| {
            for (self.outdated_object_transforms.bucketItems(bucket)) |obj_id| {
                const obj = self.scene.get(obj_id).?;
                _ = self.wasm.callFunction(self.wasm_funcs.?.recalculate_transform, .{obj.this}) catch unreachable;
                const col_array = self.wasm_transform_buffer.?;
                const transform = Mat4.fromColumnMajorPtr(col_array);
                // TODO: All objects (whether rendered or not) will have transforms
                // For now, no-op
                _ = transform;
            }
        }
        self.outdated_object_transforms.clear();
    }

    pub fn markOutdatedTransform(self: *Runtime, id: usize) void {
        self.outdated_object_transforms.put(self.allocator, @intCast(id)) catch |err| util.crash.oom(err);
    }

    fn wasmSetRoot(env: *Wasm, id: u32, this: i32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const obj = runtime.scene.get(id) orelse {
            std.log.err("tried to set root of non-existent object {d}", .{id});
            return;
        };

        obj.this = this;

        runtime.scene.setRoot(id) catch |err| {
            switch (err) {
                error.RootAlreadySet => std.log.err("tried to set root to object {d} when it's already set", .{id}),
                error.ObjectAlreadyHasParent => std.log.err("tried to set root of object {d} that already has a parent", .{id}),
            }
        };
    }

    fn wasmSetBuffers(env: *Wasm, pose_buffer: [*]f32, transform_buffer: [*]f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.wasm_pose_buffer = pose_buffer;
        runtime.wasm_transform_buffer = transform_buffer;
    }

    fn wasmCreateObject(env: *Wasm) u32 {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        return runtime.scene.createObject() catch |err| util.crash.oom(err);
    }

    fn wasmAddObjectChild(env: *Wasm, parent: u32, child: u32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.scene.addChild(parent, child) catch |err| {
            switch (err) {
                error.ObjectNotFound => std.log.err("tried to add non-existent child {d} to object {d}", .{ child, parent }),
                error.ObjectAlreadyHasParent => std.log.err("tried to add child {d} to object {d} that already has a parent", .{ child, parent }),
                error.OutOfMemory => util.crash.oom(error.OutOfMemory),
            }
        };
    }

    fn wasmNumChildren(env: *Wasm, id: u32) u32 {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const obj = runtime.scene.get(id) orelse {
            std.log.err("tried to get number of children of non-existent object {d}", .{id});
            return 0;
        };

        if (obj.children) |*children| {
            return @intCast(children.count);
        }

        return 0;
    }

    fn wasmGetChildren(env: *Wasm, id: u32, out_children: [*]i32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const obj = runtime.scene.get(id) orelse {
            std.log.err("tried to get children of non-existent object {d}", .{id});
            return;
        };

        var i: usize = 0;
        if (obj.children) |*children| {
            for (0..children.bucketCount()) |bucket| {
                for (children.bucketItems(bucket)) |child_id| {
                    out_children[i] = runtime.scene.get(child_id).?.this;
                    i += 1;
                }
            }
        }
    }

    fn wasmSetObjectPtrs(env: *Wasm, id: u32, this: i32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const obj = runtime.scene.get(id) orelse {
            std.log.err("tried to set object ptr of non-existent object {d}", .{id});
            return;
        };

        obj.this = this;
    }

    fn deleteMaterial(runtime: *Runtime, id: u32) void {
        const material_handle = Renderer.MaterialHandle{ .id = id };
        runtime.renderer.deleteMaterial(material_handle);
    }

    fn wasmRemoveObjectFromParent(env: *Wasm, id: u32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const obj = runtime.scene.get(id) orelse {
            std.log.err("tried to remove non-existent object {d}", .{id});
            return;
        };

        if (obj.parent) |parent| {
            const parent_obj = runtime.scene.get(parent) orelse {
                std.log.err("tried to delete from non-existent parent {d} of object {d}", .{ parent, obj.id });
                return;
            };

            const Dropper = struct {
                fn drop(runtime_: *Runtime, _: u32, delete_obj: *engine.Object) void {
                    delete_obj.deinit(runtime_.scene.allocator);
                    _ = runtime_.wasm.callFunction(runtime_.wasm_funcs.?.drop, .{delete_obj.this}) catch unreachable;
                }
            };

            runtime.scene.dfs(id, *Runtime, runtime, Dropper.drop) catch unreachable;
            std.debug.assert(parent_obj.children.?.delete(obj.id));
        }
    }

    fn wasmDropObject(env: *Wasm, id: u32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.scene.delete(id) catch |err| {
            switch (err) {
                error.ObjectNotFound => std.log.err("tried to delete non-existent object {d}", .{id}),
                error.ObjectHasChildren => std.log.err("tried to delete object {d} that has children", .{id}),
            }
        };

        _ = runtime.outdated_object_transforms.delete(@intCast(id));
    }

    fn wasmDropMaterial(env: *Wasm, id: u32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.renderer.dropMaterial(id);
    }

    fn wasmMarkTransformOutdated(env: *Wasm, id: u32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.markOutdatedTransform(@intCast(id));
    }

    fn wasmCreateRenderedObject(env: *Wasm, material_id: u32) u32 {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const obj = runtime.renderer.addObject(runtime.mesh, Mat4.identity(), .{ .id = material_id }, 0) catch |err| util.crash.oom(err);
        return obj.id;
    }

    fn wasmSetRenderedObjectMaterial(env: *Wasm, id: u32, material_id: u32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.renderer.setObjectMaterial(.{ .id = id }, .{ .id = material_id }) catch |err| util.crash.oom(err);
    }

    fn wasmSetRenderedObjectTransform(env: *Wasm, id: u32, transform: [*]f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.renderer.setObjectTransform(.{ .id = id }, Mat4.fromColumnMajorPtr(transform));
    }

    fn wasmDropRenderedObject(env: *Wasm, id: u32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.renderer.deleteObject(.{ .id = id });
    }

    fn wasmRandom(env: *Wasm) f32 {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        return runtime.random.random().float(f32);
    }

    fn wasmWindowWidth(env: *Wasm) i32 {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        return runtime.window.getWidth();
    }

    fn wasmWindowHeight(env: *Wasm) i32 {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        return runtime.window.getHeight();
    }

    fn wasmCreateMaterial(env: *Wasm, name: [*c]u8, r: f32, g: f32, b: f32) u32 {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const image = if (!runtime.wasm.isNullptr(name)) cond: {
            const name_slice = std.mem.span(name);
            if (runtime.assets.get(name_slice)) |image| {
                break :cond image.?;
            } else {
                std.log.err("tried to create material with non-texture asset {s}", .{name});
                return 0;
            }
        } else runtime.white_pixel_texture;

        const material = runtime.renderer.createUiMaterial(image, r, g, b) catch |err| util.crash.oom(err);
        return material.id;
    }

    fn wasmUpdateMaterial(env: *Wasm, id: u32, r: f32, g: f32, b: f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.renderer.updateMaterial(.{ .id = id }, r, g, b);
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
