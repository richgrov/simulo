const std = @import("std");
const build_options = @import("build_options");
const Logger = @import("log.zig").Logger;

const engine = @import("engine");
const Profiler = engine.profiler.Profiler;
const Mat4 = engine.math.Mat4;
const DMat3 = engine.math.DMat3;

const util = @import("util");
const reflect = util.reflect;

const fs_storage = @import("fs_storage.zig");

const pose = @import("inference/pose.zig");
pub const PoseDetector = pose.PoseDetector;

pub const Remote = if (build_options.cloud)
    @import("remote/remote.zig").Remote
else
    @import("remote/noop_remote.zig").NoOpRemote;

const DownloadPacket = @import("remote/packet.zig").DownloadPacket;

const AudioPlayer = @import("audio/audio.zig").AudioPlayer;

pub const Renderer = @import("render/renderer.zig").Renderer;
pub const Window = @import("window/window.zig").Window;

const wasm_mod = @import("wasm/wasm.zig");
pub const Wasm = wasm_mod.Wasm;
pub const WasmError = wasm_mod.Error;
const wasm_message = @import("wasm_message.zig");

const inference = @import("inference/inference.zig");
pub const Inference = inference.Inference;
pub const Detection = inference.Detection;
pub const Keypoint = inference.Keypoint;

pub const Camera = @import("camera/camera.zig").Camera;
pub const Gpu = @import("gpu/gpu.zig").Gpu;

const loadImage = @import("image/image.zig").loadImage;

const EyeGuard = @import("eyeguard.zig").EyeGuard;

const PollProiler = Profiler("runtime", enum {
    setup_frame,
    poll_window,
    resize,
    process_pose,
    update,
    render,
    process_events,
});

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

const FIRST_PROGRAM_VISIBLE_RENDER_LAYER = 8;
const MAX_PROGRAM_VISIBLE_RENDER_LAYERS = 16;

const AssetData = union(enum) {
    image: Renderer.ImageHandle,
    sound: AudioPlayer.Sound,
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

    poll_profiler: PollProiler,
    frame_count: usize,
    second_timer: i64,

    wasm: Wasm,
    wasm_entry: ?Wasm.Function,
    audio_player: AudioPlayer,
    assets: std.StringHashMap(AssetData),
    next_program: ?DownloadPacket,

    white_pixel_texture: Renderer.ImageHandle,
    chessboard: Renderer.ObjectHandle,
    mesh: Renderer.MeshHandle,
    view: Mat4,
    projection: union(enum) {
        d2: struct { near: f32, far: f32 },
        d3: struct { near: f32, far: f32, fov: f32 },
        off_axis: struct { top: f32, bottom: f32, left: f32, right: f32, near: f32, far: f32 },
    },

    calibration_state: enum {
        capturing_background,
        capturing_chessboard,
        calibrated,
    },
    eyeguard: EyeGuard,
    schedule: ?struct {
        start_ms: u64,
        stop_ms: u64,
    },
    was_running: bool,

    pub fn init(runtime: *Runtime, allocator: std.mem.Allocator, camera_id: []const u8, skip_calibration: bool) !void {
        runtime.allocator = allocator;
        runtime.logger = Logger("runtime", 2048).init();
        runtime.remote = try Remote.init(allocator);
        errdefer runtime.remote.deinit();
        try runtime.remote.start();

        runtime.poll_profiler = PollProiler.init();
        runtime.frame_count = 0;
        runtime.second_timer = 0;

        runtime.gpu = Gpu.init();
        errdefer runtime.gpu.deinit();
        runtime.window = Window.init(&runtime.gpu, "simulo runtime");
        errdefer runtime.window.deinit();
        runtime.last_window_width = 0;
        runtime.last_window_height = 0;
        runtime.renderer = try Renderer.init(&runtime.gpu, &runtime.window, allocator);
        errdefer runtime.renderer.deinit();
        runtime.pose_detector = PoseDetector.init(camera_id, if (skip_calibration) DMat3.scale(.{ 1.0 / 640.0, 1.0 / 640.0 }) else null);
        errdefer runtime.pose_detector.stop();
        runtime.calibration_state = if (skip_calibration) .calibrated else .capturing_background;

        runtime.wasm = try Wasm.init();
        errdefer runtime.wasm.deinit();
        try runtime.wasm.startWatchdog();
        try registerWasmFuncs(&runtime.wasm);
        runtime.wasm_entry = null;

        //runtime.audio_player = try AudioPlayer.init();
        //errdefer runtime.audio_player.deinit();

        runtime.assets = std.StringHashMap(AssetData).init(runtime.allocator);
        errdefer runtime.assets.deinit();

        runtime.next_program = null;

        const image = createChessboard(&runtime.renderer);
        runtime.white_pixel_texture = runtime.renderer.createImage(&[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF }, 1, 1);
        const chessboard_material = try runtime.renderer.createUiMaterial(image, 1.0, 1.0, 1.0);
        runtime.mesh = try runtime.renderer.createMesh(std.mem.asBytes(&vertices), &[_]u16{ 0, 1, 2, 2, 3, 0 });
        runtime.view = Mat4.identity();
        runtime.projection = .{ .d2 = .{ .near = -1.0, .far = 1.0 } };

        runtime.eyeguard = try EyeGuard.init(runtime.allocator, &runtime.renderer, runtime.mesh, runtime.white_pixel_texture);
        errdefer runtime.eyeguard.deinit();

        runtime.schedule = null;

        runtime.chessboard = try runtime.renderer.addObject(runtime.mesh, Mat4.identity(), chessboard_material, 31);
        errdefer runtime.renderer.deleteObject(runtime.chessboard);

        runtime.was_running = false;
    }

    pub fn deinit(self: *Runtime) void {
        self.wasm.deinit();
        self.eyeguard.deinit();

        self.assets.deinit();
        //self.audio_player.deinit();

        self.pose_detector.stop();
        self.renderer.deinit();
        self.window.deinit();
        self.gpu.deinit();
        self.remote.deinit();
    }

    fn registerWasmFuncs(wasm: *Wasm) !void {
        try wasm.exposeFunction("simulo_set_buffers", wasmSetBuffers);
        try wasm.exposeFunction("simulo_poll", wasmPoll);

        try wasm.exposeFunction("simulo_create_rendered_object2", wasmCreateRenderedObject2);
        try wasm.exposeFunction("simulo_set_rendered_object_material", wasmSetRenderedObjectMaterial);
        try wasm.exposeFunction("simulo_set_rendered_object_transforms", wasmSetRenderedObjectTransforms);
        try wasm.exposeFunction("simulo_drop_rendered_object", wasmDropRenderedObject);

        try wasm.exposeFunction("simulo_set_camera_2d", wasmSetCamera2d);
        try wasm.exposeFunction("simulo_set_camera_3d", wasmSetCamera3d);
        try wasm.exposeFunction("simulo_set_camera_off_axis", wasmSetCameraOffAxis);
        try wasm.exposeFunction("simulo_set_view_matrix", wasmSetViewMatrix);

        try wasm.exposeFunction("simulo_window_width", wasmWindowWidth);
        try wasm.exposeFunction("simulo_window_height", wasmWindowHeight);

        try wasm.exposeFunction("simulo_create_material", wasmCreateMaterial);
        try wasm.exposeFunction("simulo_update_material", wasmUpdateMaterial);
        try wasm.exposeFunction("simulo_drop_material", wasmDropMaterial);
    }

    fn loadProgram(self: *Runtime, program_path: []const u8, assets: []const fs_storage.ProgramAsset) !void {
        self.logger.info("Reading program from {s}", .{program_path});
        const data = try std.fs.cwd().readFileAlloc(self.allocator, program_path, std.math.maxInt(usize));
        defer self.allocator.free(data);

        try self.wasm.load(data);

        const init_func = self.wasm.getFunction("_start") orelse {
            self.logger.err("program missing init function", .{});
            return error.MissingFunction;
        };

        self.wasm_entry = init_func;

        for (assets) |*asset| {
            const asset_name = asset.name.?.items();

            const file_data = std.fs.cwd().readFileAlloc(self.allocator, asset.real_path, 10 * 1024 * 1024) catch |err| {
                self.logger.err("failed to read asset file at {s}: {s}", .{ asset.real_path, @errorName(err) });
                return error.AssetReadFailed;
            };
            defer self.allocator.free(file_data);

            self.logger.info("loading asset: {s}", .{asset_name});

            if (std.mem.endsWith(u8, asset_name, ".png")) {
                const image_info = loadImage(file_data) catch |err| {
                    self.logger.err("failed to load data from {s}: {s}", .{ asset.real_path, @errorName(err) });
                    return error.AssertLoadFailed;
                };

                if (image_info.data.len > 1024 * 1024 * 8) {
                    self.logger.err("image {s} is too large: {d}", .{ asset_name, image_info.data.len });
                    return error.ImageTooLarge;
                }

                const image = self.renderer.createImage(image_info.data, image_info.width, image_info.height);

                const name = self.allocator.dupe(u8, asset_name) catch |err| util.crash.oom(err);
                self.assets.put(name, .{ .image = image }) catch |err| util.crash.oom(err);
            } else if (std.mem.endsWith(u8, asset_name, ".wav")) {
                const sound = self.audio_player.loadSound(file_data) catch |err| {
                    self.logger.err("failed to load sound from {s}: {s}", .{ asset.real_path, @errorName(err) });
                    return error.AssertLoadFailed;
                };

                const name = self.allocator.dupe(u8, asset_name) catch |err| util.crash.oom(err);
                self.assets.put(name, .{ .sound = sound }) catch |err| util.crash.oom(err);
            } else {
                self.logger.err("unsupported asset: {s}", .{asset_name});
            }
        }
    }

    fn disposeCurrentProgram(self: *Runtime) void {
        var assets_keys = self.assets.iterator();
        while (assets_keys.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            switch (entry.value_ptr.*) {
                .sound => |*sound| {
                    self.audio_player.unloadSound(sound);
                },
                .image => |_| {
                    // TODO: delete image if present
                },
            }
        }
        self.assets.clearRetainingCapacity();

        self.wasm_entry = null;

        for (FIRST_PROGRAM_VISIBLE_RENDER_LAYER..FIRST_PROGRAM_VISIBLE_RENDER_LAYER + MAX_PROGRAM_VISIBLE_RENDER_LAYERS) |layer| {
            self.renderer.clearLayer(@intCast(layer));
        }
        self.renderer.clearUiMaterials();
    }

    fn runLocalProgram(self: *Runtime, program_path: []const u8, assets_path: []const u8) !void {
        var asset_dir = std.fs.cwd().openDir(assets_path, .{ .iterate = true }) catch |err| {
            self.logger.err("failed to access directory {s}: {s}", .{ assets_path, @errorName(err) });
            return err;
        };
        defer asset_dir.close();

        var path_buf: [4 * 1024]u8 = undefined;
        var path_allocator = std.heap.FixedBufferAllocator.init(&path_buf);
        var assets = std.ArrayList(fs_storage.ProgramAsset).initCapacity(path_allocator.allocator(), 8) catch unreachable;
        defer assets.deinit(path_allocator.allocator());

        var files = asset_dir.iterate();
        while (true) {
            const file = files.next() catch |err| {
                self.logger.err("failed to access file in directory {s}: {s}", .{ assets_path, @errorName(err) });
                return err;
            } orelse break;

            if (std.mem.endsWith(u8, file.name, ".png")) {
                const real_path = try std.fs.path.joinZ(path_allocator.allocator(), &.{ assets_path, file.name });
                try assets.append(path_allocator.allocator(), .{
                    .name = util.FixedArrayList(u8, fs_storage.max_asset_name_len).initFrom(file.name) catch unreachable,
                    .real_path = real_path,
                });
            }
        }

        try self.loadProgram(program_path, assets.items);
    }

    fn tryRunLatestProgram(self: *Runtime) void {
        var buf: [1024 * 4]u8 = undefined;
        var allocator = std.heap.FixedBufferAllocator.init(&buf);
        const program_info = fs_storage.loadLatestProgram(allocator.allocator()) catch |err| {
            self.logger.err("failed to load latest program: {s}", .{@errorName(err)});
            return;
        };

        if (program_info) |info| {
            self.loadProgram(info.program_path, info.assets.items()) catch |err| {
                self.logger.err("failed to run latest program: {s}", .{@errorName(err)});
            };
        }
    }

    pub fn run(self: *Runtime, local_paths: struct { program: ?[]const u8, assets: ?[]const u8 }) !void {
        const time_of_day = @mod(std.time.milliTimestamp(), 24 * 60 * 60 * 1000);
        self.was_running = self.shouldRun(time_of_day);
        self.logger.info("initial run state: {}", .{self.was_running});
        if (self.was_running) {
            try self.pose_detector.start();
        }

        if (local_paths.program) |program| {
            self.runLocalProgram(program, local_paths.assets.?) catch |err| {
                self.logger.err("error running local program: {s}", .{@errorName(err)});
                return;
            };
        } else {
            self.tryRunLatestProgram();
        }

        while (self.poll(null) != null) {
            if (self.calibration_state == .calibrated) {
                if (self.wasm_entry) |wasm_entry| {
                    _ = self.wasm.callFunction(wasm_entry, .{}) catch |err| {
                        self.logger.err("failed to run program: {s}", .{@errorName(err)});
                    };

                    self.disposeCurrentProgram();
                }

                if (self.next_program) |*program| {
                    self.loadProgram(program.program_path, program.files) catch |err| {
                        self.logger.err("failed to load new program: {s}", .{@errorName(err)});
                    };
                    program.deinit(self.allocator);
                    self.next_program = null;
                }
            }
        }

        self.disposeCurrentProgram();
    }

    fn poll(self: *Runtime, event_buf: ?[]u8) ?usize {
        self.poll_profiler.reset();

        const now = std.time.milliTimestamp();

        const time_of_day = @mod(now, 24 * 60 * 60 * 1000);
        const run_state = self.shouldRun(time_of_day);
        if (run_state != self.was_running) {
            self.logger.info("run state changed: {} -> {}", .{ self.was_running, run_state });
            if (run_state) {
                self.pose_detector.start() catch |err| {
                    self.logger.err("failed to start pose detector: {s}", .{@errorName(err)});
                };
            } else {
                self.pose_detector.stop();
            }
            self.was_running = run_state;
        }

        const width = self.window.getWidth();
        const height = self.window.getHeight();
        self.poll_profiler.log(.setup_frame);

        if (!self.window.poll()) {
            return null;
        }

        self.poll_profiler.log(.poll_window);

        if (width != self.last_window_width or height != self.last_window_height) {
            self.last_window_width = width;
            self.last_window_height = height;

            if (comptime util.vulkan) {
                self.renderer.handleResize(width, height, self.window.surface());
            }

            self.renderer.setObjectTransform(self.chessboard, switch (self.calibration_state) {
                .capturing_chessboard => Mat4.scale(.{ @floatFromInt(width), @floatFromInt(height), 1 }),
                else => Mat4.zero(),
            });

            self.poll_profiler.log(.resize);
        }

        const event_out_len = self.processPoseDetections(event_buf) catch |err| blk: {
            self.logger.err("failed to process pose detections: {s}", .{@errorName(err)});
            break :blk 0;
        };
        self.poll_profiler.log(.process_pose);

        if (self.was_running) {
            const w: f32 = @floatFromInt(width);
            const h: f32 = @floatFromInt(height);

            const projection = switch (self.projection) {
                .d2 => Mat4.ortho(w, h, -1.0, 1.0),
                .d3 => |d| Mat4.perspective(w / h, d.fov, d.near, d.far),
                .off_axis => |d| Mat4.offAxisPerspective(d.top, d.bottom, d.left, d.right, d.near, d.far),
            };

            const view_projection = projection.matmul(&self.view);

            self.renderer.render(&self.window, &view_projection, &view_projection) catch |err| {
                self.logger.err("render failed: {any}", .{err});
            };
        }

        self.poll_profiler.log(.render);

        while (self.remote.nextMessage()) |msg| {
            var message = msg;

            switch (message) {
                .download => |download| {
                    fs_storage.storeLatestProgram(download.program_path, download.files) catch |err| {
                        self.logger.err("failed to store latest info: {s}", .{@errorName(err)});
                    };

                    self.next_program = download;
                },
                .schedule => |maybe_schedule| {
                    defer message.deinit(self.allocator);

                    if (maybe_schedule) |sched| {
                        self.logger.info("remote set schedule to {D}-{D}", .{
                            sched.start_ms * std.time.ns_per_ms,
                            sched.stop_ms * std.time.ns_per_ms,
                        });
                        self.schedule = .{
                            .start_ms = sched.start_ms,
                            .stop_ms = sched.stop_ms,
                        };
                    } else {
                        self.logger.info("remote removed schedule", .{});
                        self.schedule = null;
                    }
                },
            }
        }

        self.poll_profiler.log(.process_events);

        self.frame_count += 1;
        if (now - self.second_timer >= 1000) {
            if (self.frame_count < 59) {
                self.logger.warn("Low FPS ({d}), {f}", .{ self.frame_count, &self.poll_profiler });
            } else {
                self.logger.debug("FPS: {d}", .{self.frame_count});
            }
            self.frame_count = 0;
            self.second_timer = now;
        }

        return event_out_len;
    }

    fn processPoseDetections(self: *Runtime, event_buf: ?[]u8) !usize {
        const width: f32 = @floatFromInt(self.last_window_width);
        const height: f32 = @floatFromInt(self.last_window_height);

        var writer = if (event_buf) |buf| std.io.Writer.fixed(buf) else null;

        while (self.pose_detector.nextEvent()) |event| {
            switch (event) {
                .calibration_background_set => {
                    self.logger.info("capturing chessboard", .{});
                    self.calibration_state = .capturing_chessboard;
                    self.renderer.setObjectTransform(self.chessboard, Mat4.scale(.{ width, height, 1 }));
                },
                .calibration_calibrated => {
                    self.calibration_state = .calibrated;
                    self.renderer.setObjectTransform(self.chessboard, Mat4.zero());
                },
                .move => |move| {
                    self.eyeguard.handleEvent(move.id, &move.detection, &self.renderer, width, height);

                    if (writer) |*w| {
                        wasm_message.writeMoveEvent(w, move.id, &move.detection, width, height) catch |err| {
                            self.logger.err("failed to write move event: {s}", .{@errorName(err)});
                        };
                    }
                },
                .lost => |id| {
                    self.eyeguard.handleDelete(&self.renderer, id);

                    if (writer) |*w| {
                        wasm_message.writeLostEvent(w, id) catch |err| {
                            self.logger.err("failed to write lost event: {s}", .{@errorName(err)});
                        };
                    }
                },
                .fault => |fault| {
                    switch (fault.category) {
                        .camera_init, .inference_init, .calibrate_init, .camera_stall, .background_swap, .set_background => {
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

        return if (writer) |*w| w.end else 0;
    }

    fn wasmSetBuffers(env: *Wasm, pose_buffer: [*]f32) void {
        _ = env;
        _ = pose_buffer;
        // kept for backwards compatibility
    }

    fn wasmPoll(env: *Wasm, buf: [*]u8, buf_len: u32) i32 {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));

        const event_out_len = runtime.poll(buf[0..buf_len]) orelse {
            return -1;
        };

        if (!runtime.was_running) {
            return -1;
        }

        runtime.wasm.extendTimeout();
        return @intCast(event_out_len);
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
        const obj = runtime.renderer.addObject(
            runtime.mesh,
            Mat4.identity(),
            .{ .id = material_id },
            FIRST_PROGRAM_VISIBLE_RENDER_LAYER,
        ) catch |err| util.crash.oom(err);
        return obj.id;
    }

    fn wasmCreateRenderedObject2(env: *Wasm, material_id: u32, render_order: u32) u32 {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        if (render_order >= MAX_PROGRAM_VISIBLE_RENDER_LAYERS) {
            runtime.logger.err("tried to create rendered object with render order {d}", .{render_order});
            return 0;
        }
        runtime.logger.trace("simulo_create_rendered_object2({d}, {d})", .{ material_id, render_order });
        const obj = runtime.renderer.addObject(
            runtime.mesh,
            Mat4.identity(),
            .{ .id = material_id },
            FIRST_PROGRAM_VISIBLE_RENDER_LAYER + @as(u8, @intCast(render_order)),
        ) catch |err| util.crash.oom(err);
        return obj.id;
    }

    fn wasmSetRenderedObjectMaterial(env: *Wasm, id: u32, material_id: u32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.renderer.setObjectMaterial(.{ .id = id }, .{ .id = material_id }) catch |err| util.crash.oom(err);
    }

    fn wasmSetRenderedObjectTransforms(env: *Wasm, count: u32, ids: [*]u32, transforms: [*]f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.logger.trace("simulo_set_rendered_object_transforms({d}, {*}, {*})", .{ count, ids, transforms });

        for (0..count) |i| {
            const mat = Mat4.fromColumnMajorPtr(@ptrCast(&transforms[i * 16]));
            runtime.renderer.setObjectTransform(.{ .id = ids[i] }, mat);
        }
    }

    fn wasmDropRenderedObject(env: *Wasm, id: u32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.logger.trace("simulo_drop_rendered_object({d})", .{id});
        runtime.renderer.deleteObject(.{ .id = id });
    }

    fn wasmSetCamera2d(env: *Wasm, near: f32, far: f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.projection = .{ .d2 = .{ .near = near, .far = far } };
    }

    fn wasmSetCamera3d(env: *Wasm, fov: f32, near: f32, far: f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.projection = .{ .d3 = .{ .fov = fov, .near = near, .far = far } };
    }

    fn wasmSetCameraOffAxis(env: *Wasm, top: f32, bottom: f32, left: f32, right: f32, near: f32, far: f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.projection = .{ .off_axis = .{ .top = top, .bottom = bottom, .left = left, .right = right, .near = near, .far = far } };
    }

    fn wasmSetViewMatrix(env: *Wasm, matrix: [*]f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.view = Mat4.fromColumnMajorPtr(matrix);
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
            if (runtime.assets.get(name_slice)) |asset| {
                switch (asset) {
                    .image => |img| break :cond img,
                    .sound => |_| {
                        runtime.logger.err("tried to create material with sound asset {s}", .{name_slice});
                        return 0;
                    },
                }
            } else {
                runtime.logger.err("tried to create material with non-existent asset {s}", .{name_slice});
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

    fn shouldRun(self: *Runtime, time_of_day: i64) bool {
        const time: u64 = @intCast(time_of_day);
        if (self.schedule) |sched| {
            if (sched.start_ms > sched.stop_ms) {
                // the active schedule runs over midnight across two days
                return time >= sched.start_ms or time <= sched.stop_ms;
            }

            return time >= sched.start_ms and time <= sched.stop_ms;
        } else {
            return true;
        }
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
