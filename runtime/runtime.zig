const std = @import("std");
const build_options = @import("build_options");
const Logger = @import("log.zig").Logger;

const engine = @import("engine");
const Profiler = engine.profiler.Profiler;
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

const wasm_mod = @import("wasm/wasm.zig");
pub const Wasm = wasm_mod.Wasm;
pub const WasmError = wasm_mod.Error;

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

const Asset = struct {
    name: []const u8,
    real_path: []const u8,
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
    logger: Logger("runtime", 2048),

    wasm: Wasm,
    wasm_funcs: ?struct {
        init: Wasm.Function,
        update: Wasm.Function,
        pose: Wasm.Function,
    },
    wasm_pose_buffer: ?[*]f32,
    assets: std.StringHashMap(?Renderer.ImageHandle),

    white_pixel_texture: Renderer.ImageHandle,
    chessboard: Renderer.ObjectHandle,
    mesh: Renderer.MeshHandle,
    calibrated: bool,
    eyeguard: EyeGuard,
    schedule: ?struct {
        start_ms: u64,
        stop_ms: u64,
    },

    pub fn init(runtime: *Runtime, allocator: std.mem.Allocator, camera_id: []const u8) !void {
        runtime.allocator = allocator;
        runtime.logger = Logger("runtime", 2048).init();
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
        runtime.pose_detector = PoseDetector.init(camera_id);
        errdefer runtime.pose_detector.stop();
        runtime.calibrated = false;

        runtime.wasm = try Wasm.init();
        errdefer runtime.wasm.deinit();
        try registerWasmFuncs(&runtime.wasm);
        runtime.wasm_funcs = null;
        runtime.wasm_pose_buffer = null;

        runtime.assets = std.StringHashMap(?Renderer.ImageHandle).init(runtime.allocator);
        errdefer runtime.assets.deinit();

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
        self.wasm.deinit();
        self.eyeguard.deinit();

        var assets_keys = self.assets.keyIterator();
        while (assets_keys.next()) |key| {
            self.allocator.free(key.*);
        }
        self.assets.deinit();

        self.pose_detector.stop();
        self.renderer.deinit();
        self.window.deinit();
        self.gpu.deinit();
        self.remote.deinit();
    }

    fn registerWasmFuncs(wasm: *Wasm) !void {
        try wasm.exposeFunction("simulo_set_buffers", wasmSetBuffers);

        try wasm.exposeFunction("simulo_create_rendered_object", wasmCreateRenderedObject);
        try wasm.exposeFunction("simulo_set_rendered_object_material", wasmSetRenderedObjectMaterial);
        try wasm.exposeFunction("simulo_set_rendered_object_transform", wasmSetRenderedObjectTransform);
        try wasm.exposeFunction("simulo_drop_rendered_object", wasmDropRenderedObject);

        try wasm.exposeFunction("simulo_window_width", wasmWindowWidth);
        try wasm.exposeFunction("simulo_window_height", wasmWindowHeight);

        try wasm.exposeFunction("simulo_create_material", wasmCreateMaterial);
        try wasm.exposeFunction("simulo_update_material", wasmUpdateMaterial);
        try wasm.exposeFunction("simulo_drop_material", wasmDropMaterial);
    }

    fn runProgram(self: *Runtime, program_path: []const u8, assets: []const Asset) !void {
        var assets_keys = self.assets.iterator();
        while (assets_keys.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            // TODO: delete image if present
        }
        self.assets.clearRetainingCapacity();

        self.logger.info("Reading program from {s}", .{program_path});
        const data = try std.fs.cwd().readFileAlloc(self.allocator, program_path, std.math.maxInt(usize));
        defer self.allocator.free(data);

        try self.wasm.load(data);

        const init_func = self.wasm.getFunction("simulo_main") orelse {
            self.logger.err("program missing init function", .{});
            return error.MissingFunction;
        };

        self.wasm_funcs = .{
            .init = init_func,
            .update = self.wasm.getFunction("simulo__update") orelse {
                self.logger.err("program missing update function", .{});
                return error.MissingFunction;
            },
            .pose = self.wasm.getFunction("simulo__pose") orelse {
                self.logger.err("program missing pose function", .{});
                return error.MissingFunction;
            },
        };
        self.wasm_pose_buffer = null;

        for (assets) |*asset| {
            const image_data = std.fs.cwd().readFileAlloc(self.allocator, asset.real_path, 10 * 1024 * 1024) catch |err| {
                self.logger.err("failed to read asset file at {s}: {s}", .{ asset.real_path, @errorName(err) });
                return error.AssertReadFailed;
            };
            defer self.allocator.free(image_data);

            const image_info = loadImage(image_data) catch |err| {
                self.logger.err("failed to load data from {s}: {s}", .{ asset.real_path, @errorName(err) });
                return error.AssertLoadFailed;
            };

            const image = self.renderer.createImage(image_info.data, image_info.width, image_info.height);

            const name = self.allocator.dupe(u8, asset.name) catch |err| util.crash.oom(err);
            self.assets.put(name, image) catch |err| util.crash.oom(err);
        }

        if (self.calibrated) {
            _ = self.wasm.callFunction(init_func, .{}) catch unreachable;

            if (self.wasm_pose_buffer == null) {
                return error.BuffersNotInitialized;
            }
        }
    }

    fn runLocalProgram(self: *Runtime, path: []const u8) !void {
        var asset_dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
            self.logger.err("failed to access directory {s}: {s}", .{ path, @errorName(err) });
            return err;
        };
        defer asset_dir.close();

        var path_buf: [4 * 1024]u8 = undefined;
        var path_allocator = std.heap.FixedBufferAllocator.init(&path_buf);
        var assets = std.ArrayList(Asset).initCapacity(path_allocator.allocator(), 8) catch unreachable;
        defer assets.deinit(path_allocator.allocator());

        var program_path: ?[]const u8 = null;

        var files = asset_dir.iterate();
        while (true) {
            const file = files.next() catch |err| {
                self.logger.err("failed to access file in directory {s}: {s}", .{ path, @errorName(err) });
                return err;
            } orelse break;

            const name = try path_allocator.allocator().dupe(u8, file.name);
            if (std.mem.eql(u8, name, "main.wasm")) {
                program_path = try std.fs.path.join(path_allocator.allocator(), &.{ path, name });
            } else if (std.mem.endsWith(u8, name, ".png")) {
                const real_path = try std.fs.path.join(path_allocator.allocator(), &.{ path, name });
                try assets.append(path_allocator.allocator(), .{
                    .name = name,
                    .real_path = real_path,
                });
            }
        }

        if (program_path) |prog| {
            try self.runProgram(prog, assets.items);
        } else {
            self.logger.err("the path {s} doesn't contain a main.wasm file", .{path});
        }
    }

    fn tryRunLatestProgram(self: *Runtime) void {
        const program_info = fs_storage.loadLatestProgram() catch |err| {
            self.logger.err("failed to load latest program: {s}", .{@errorName(err)});
            return;
        };

        if (program_info) |info| {
            var program_path_buf: [1024]u8 = undefined;
            const program_path = fs_storage.getCachePath(&program_path_buf, &info.program_hash) catch unreachable;

            var path_buf: [4 * 1024]u8 = undefined;
            var path_allocator = std.heap.FixedBufferAllocator.init(&path_buf);
            var assets = std.ArrayList(Asset).initCapacity(path_allocator.allocator(), info.assets.len) catch {
                self.logger.err("latest program had too many assets", .{});
                return;
            };
            defer assets.deinit(path_allocator.allocator());

            for (info.assets.items()) |*asset| {
                const real_path = fs_storage.getCachePathAlloc(path_allocator.allocator(), &asset.hash) catch unreachable;

                assets.appendAssumeCapacity(.{
                    .name = asset.name.?.items(),
                    .real_path = real_path,
                });
            }

            self.runProgram(program_path, assets.items) catch |err| {
                self.logger.err("failed to run latest program: {s}", .{@errorName(err)});
            };
        }
    }

    pub fn run(self: *Runtime, local_asset_path: ?[]const u8) !void {
        if (local_asset_path) |path| {
            self.runLocalProgram(path) catch |err| {
                self.logger.err("error running local program: {s}", .{@errorName(err)});
                return;
            };
        } else {
            self.tryRunLatestProgram();
        }

        try self.pose_detector.start();
        var last_time = std.time.milliTimestamp();

        var frame_count: usize = 0;
        var second_timer: i64 = std.time.milliTimestamp();

        const RuntimeProiler = Profiler("runtime", enum {
            setup_frame,
            resize,
            process_pose,
            update,
            render,
            process_events,
        });
        var profiler = RuntimeProiler.init();

        while (self.window.poll()) {
            profiler.reset();

            const now = std.time.milliTimestamp();
            const delta = now - last_time;
            last_time = now;

            const width = self.window.getWidth();
            const height = self.window.getHeight();
            profiler.log(.setup_frame);

            if (width != self.last_window_width or height != self.last_window_height) {
                self.last_window_width = width;
                self.last_window_height = height;

                if (comptime util.vulkan) {
                    self.renderer.handleResize(width, height, self.window.surface());
                }

                self.renderer.setObjectTransform(self.chessboard, if (self.calibrated) Mat4.zero() else Mat4.scale(.{ @floatFromInt(width), @floatFromInt(height), 1 }));

                profiler.log(.resize);
            }

            try self.processPoseDetections();
            profiler.log(.process_pose);

            if (self.calibrated) {
                const deltaf: f32 = @floatFromInt(delta);
                _ = self.wasm.callFunction(self.wasm_funcs.?.update, .{deltaf / 1000.0}) catch unreachable;
                profiler.log(.update);
            }

            const ui_projection = Mat4.ortho(
                @floatFromInt(self.last_window_width),
                @floatFromInt(self.last_window_height),
                -1.0,
                1.0,
            );
            self.renderer.render(&self.window, &ui_projection, &ui_projection) catch |err| {
                self.logger.err("render failed: {any}", .{err});
            };
            profiler.log(.render);

            while (self.remote.nextMessage()) |msg| {
                var message = msg;
                defer message.deinit(self.allocator);

                switch (message) {
                    .download => |download| {
                        var should_run = true;

                        var program_path_buf: [1024]u8 = undefined;
                        const program_path = fs_storage.getCachePath(&program_path_buf, &download.program_hash) catch unreachable;

                        self.remote.fetch(download.program_url, &download.program_hash, program_path) catch |err| {
                            self.logger.err("program download failed: {s}", .{@errorName(err)});
                            should_run = false;
                        };

                        var path_buf: [4 * 1024]u8 = undefined;
                        var path_allocator = std.heap.FixedBufferAllocator.init(&path_buf);
                        var assets = try std.ArrayList(Asset).initCapacity(path_allocator.allocator(), download.files.len);
                        defer assets.deinit(path_allocator.allocator());

                        var program_assets = try std.ArrayList(fs_storage.ProgramAsset).initCapacity(path_allocator.allocator(), download.files.len);
                        defer program_assets.deinit(path_allocator.allocator());

                        for (download.files) |file| {
                            const dest_path = fs_storage.getCachePathAlloc(path_allocator.allocator(), &file.asset.hash) catch unreachable;

                            self.remote.fetch(file.url, &file.asset.hash, dest_path) catch |err| {
                                self.logger.err("asset download failed: {s}", .{@errorName(err)});
                                should_run = false;
                            };

                            assets.appendAssumeCapacity(.{
                                .name = file.asset.name.?.items(),
                                .real_path = dest_path,
                            });

                            program_assets.appendAssumeCapacity(file.asset);
                        }

                        fs_storage.storeLatestProgram(&download.program_hash, program_assets.items) catch |err| {
                            self.logger.err("failed to store latest info: {s}", .{@errorName(err)});
                        };

                        if (should_run) {
                            try self.runProgram(program_path, assets.items);
                        }
                    },
                    .schedule => |maybe_schedule| {
                        if (maybe_schedule) |sched| {
                            self.schedule = .{
                                .start_ms = sched.start_ms,
                                .stop_ms = sched.stop_ms,
                            };
                        } else {
                            self.schedule = null;
                        }
                    },
                }
            }

            profiler.log(.process_events);

            frame_count += 1;
            if (now - second_timer >= 1000) {
                if (frame_count < 59) {
                    self.logger.warn("Low FPS ({d}), {f}", .{ frame_count, &profiler });
                } else {
                    self.logger.debug("FPS: {d}", .{frame_count});
                }
                frame_count = 0;
                second_timer = now;
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
                            _ = self.wasm.callFunction(funcs.init, .{}) catch unreachable;

                            if (self.wasm_pose_buffer == null) {
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
                .fault => |fault| {
                    switch (fault.category) {
                        .camera_init, .inference_init, .calibrate_init => {
                            self.logger.err("pose detector fatal fault: {s}: {any}", .{ @tagName(fault.category), fault.err });
                            return fault.err;
                        },
                        .inference_run, .camera_swap, .calibrate => {
                            self.logger.err("pose detector fault: {s}: {any}", .{ @tagName(fault.category), fault.err });
                        },
                    }
                },
            }
        }
    }

    fn wasmSetBuffers(env: *Wasm, pose_buffer: [*]f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.wasm_pose_buffer = pose_buffer;
    }

    fn deleteMaterial(runtime: *Runtime, id: u32) void {
        const material_handle = Renderer.MaterialHandle{ .id = id };
        runtime.renderer.deleteMaterial(material_handle);
    }

    fn wasmDropMaterial(env: *Wasm, id: u32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.renderer.dropMaterial(id);
    }

    fn wasmCreateRenderedObject(env: *Wasm, material_id: u32) u32 {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.logger.trace("simulo_create_rendered_object({d})", .{material_id});
        const obj = runtime.renderer.addObject(runtime.mesh, Mat4.identity(), .{ .id = material_id }, 0) catch |err| util.crash.oom(err);
        return obj.id;
    }

    fn wasmSetRenderedObjectMaterial(env: *Wasm, id: u32, material_id: u32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.renderer.setObjectMaterial(.{ .id = id }, .{ .id = material_id }) catch |err| util.crash.oom(err);
    }

    fn wasmSetRenderedObjectTransform(env: *Wasm, id: u32, transform: [*]f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const mat = Mat4.fromColumnMajorPtr(transform);
        runtime.logger.trace("simulo_set_rendered_object_transform({d}, {f})", .{ id, mat });
        runtime.renderer.setObjectTransform(.{ .id = id }, mat);
    }

    fn wasmDropRenderedObject(env: *Wasm, id: u32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.logger.trace("simulo_drop_rendered_object({d})", .{id});
        runtime.renderer.deleteObject(.{ .id = id });
    }

    fn wasmWindowWidth(env: *Wasm) i32 {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        return runtime.window.getWidth();
    }

    fn wasmWindowHeight(env: *Wasm) i32 {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        return runtime.window.getHeight();
    }

    fn wasmCreateMaterial(env: *Wasm, name: [*c]u8, name_len: u32, r: f32, g: f32, b: f32) u32 {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const image = if (!runtime.wasm.isNullptr(name)) cond: {
            const name_slice = name[0..name_len];
            runtime.logger.trace("simulo_create_material(\"{s}\", {d}, {d}, {d})", .{ name_slice, r, g, b });
            if (runtime.assets.get(name_slice)) |image| {
                break :cond image.?;
            } else {
                runtime.logger.err("tried to create material with non-existent asset {s}", .{name});
                return 0;
            }
        } else cond: {
            runtime.logger.trace("simulo_create_material(null, {d}, {d}, {d})", .{ r, g, b });
            break :cond runtime.white_pixel_texture;
        };

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
