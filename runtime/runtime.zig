const std = @import("std");
const build_options = @import("build_options");
const Logger = @import("log.zig").Logger;

const engine = @import("engine");
const Profiler = engine.profiler.Profiler;
const Mat4 = engine.math.Mat4;
const DMat3 = engine.math.DMat3;

const util = @import("util");
const reflect = util.reflect;

const DeviceConfig = @import("device/config.zig").DeviceConfig;
const devices = @import("device/device.zig");
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

const PollProfiler = Profiler("runtime", enum {
    setup_frame,
    poll_window,
    resize,
    process_pose,
    update,
    render,
    process_events,
});

const AssetData = union(enum) {
    image: Renderer.ImageHandle,
    sound: AudioPlayer.Sound,
};

pub const DeviceId = struct { index: usize };

pub const LocalRun = struct {
    program: []const u8,
    assets: []const u8,
    devices: *const DeviceConfig,
};

pub const Runtime = struct {
    remote: Remote,
    allocator: std.mem.Allocator,
    logger: Logger("runtime", 2048),

    poll_profiler: PollProfiler,
    frame_count: usize,
    second_timer: i64,

    wasm: Wasm,
    wasm_entry: ?Wasm.Function,
    first_poll: bool,
    audio_player: AudioPlayer,
    assets: std.StringHashMap(AssetData),
    next_program: ?DownloadPacket,
    devices: std.ArrayList(devices.Device),
    calibrations_remaining: usize,

    schedule: ?struct {
        start_ms: u64,
        stop_ms: u64,
    },
    was_running: bool,

    pub fn init(runtime: *Runtime, allocator: std.mem.Allocator) !void {
        runtime.allocator = allocator;
        runtime.logger = Logger("runtime", 2048).init();
        runtime.remote = try Remote.init(allocator);
        errdefer runtime.remote.deinit();
        try runtime.remote.start();

        runtime.poll_profiler = PollProfiler.init();
        runtime.frame_count = 0;
        runtime.second_timer = 0;

        runtime.wasm = try Wasm.init();
        errdefer runtime.wasm.deinit();
        try runtime.wasm.startWatchdog();
        try registerWasmFuncs(&runtime.wasm);
        runtime.wasm_entry = null;
        runtime.first_poll = false;

        //runtime.audio_player = try AudioPlayer.init();
        //errdefer runtime.audio_player.deinit();

        runtime.assets = std.StringHashMap(AssetData).init(runtime.allocator);
        errdefer runtime.assets.deinit();

        runtime.next_program = null;
        runtime.devices = std.ArrayList(devices.Device).initCapacity(runtime.allocator, 0) catch unreachable;
        runtime.calibrations_remaining = 0;

        runtime.schedule = null;

        runtime.was_running = false;
    }

    pub fn deinit(self: *Runtime) void {
        self.wasm.deinit();

        self.assets.deinit();
        //self.audio_player.deinit();
        for (self.devices.items) |*device| {
            device.deinit(self);
        }
        self.devices.deinit(self.allocator);

        self.remote.deinit();
    }

    fn registerWasmFuncs(wasm: *Wasm) !void {
        try wasm.exposeFunction("simulo_set_buffers", wasmSetBuffers);
        try wasm.exposeFunction("simulo_poll", wasmPoll);

        try wasm.exposeFunction("simulo_create_rendered_object2", wasmCreateRenderedObject2);
        try wasm.exposeFunction("simulo_set_rendered_object_material", wasmSetRenderedObjectMaterial);
        try wasm.exposeFunction("simulo_set_rendered_object_transforms", wasmSetRenderedObjectTransforms);
        try wasm.exposeFunction("simulo_set_rendered_object_colors", wasmSetRenderedObjectColors);
        try wasm.exposeFunction("simulo_drop_rendered_object", wasmDropRenderedObject);

        try wasm.exposeFunction("simulo_set_camera_2d", wasmSetCamera2d);
        try wasm.exposeFunction("simulo_set_camera_3d", wasmSetCamera3d);
        try wasm.exposeFunction("simulo_set_camera_off_axis", wasmSetCameraOffAxis);
        try wasm.exposeFunction("simulo_set_view_matrix", wasmSetViewMatrix);

        try wasm.exposeFunction("simulo_create_material", wasmCreateMaterial);
        try wasm.exposeFunction("simulo_update_material", wasmUpdateMaterial);
        try wasm.exposeFunction("simulo_drop_material", wasmDropMaterial);
    }

    fn applyDeviceConfig(self: *Runtime, devices_config: *const DeviceConfig) !void {
        const device_map = &devices_config.devices;
        var new_devices = try std.ArrayList(devices.Device).initCapacity(self.allocator, device_map.count());
        errdefer {
            for (new_devices.items) |*device| {
                device.deinit(self);
            }
            new_devices.deinit(self.allocator);
        }

        var display_count: usize = 0;
        var device_iter = device_map.iterator();
        while (device_iter.next()) |entry| {
            const id = entry.key_ptr.*;
            const device_type: devices.DeviceType = switch (entry.value_ptr.*) {
                .camera => |*camera| .{ .camera = devices.CameraDevice.init(camera.port_path, self) },

                .projector => |*projector| blk: {
                    if (!projector.skip_calibration) display_count += 1;
                    break :blk .{ .display = try devices.DisplayDevice.init(
                        self.allocator,
                        if (projector.skip_calibration) DMat3.scale(.{ 1.0 / 640.0, 1.0 / 640.0 }) else null,
                        projector.port_path,
                    ) };
                },
            };

            try new_devices.append(self.allocator, devices.Device.init(id, device_type));
        }

        for (self.devices.items) |*device| {
            device.deinit(self);
        }
        self.devices.deinit(self.allocator);

        self.devices = new_devices;
        self.calibrations_remaining = display_count;
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
        self.first_poll = true;

        for (assets) |*asset| {
            const asset_name = asset.name.?.items();

            const file_data = std.fs.cwd().readFileAlloc(self.allocator, asset.real_path, 10 * 1024 * 1024) catch |err| {
                self.logger.err("failed to read asset file at {s}: {s}", .{ asset.real_path, @errorName(err) });
                return error.AssetReadFailed;
            };
            defer self.allocator.free(file_data);

            self.logger.info("loading asset: {s}", .{asset_name});
            const renderer = &self.tempGetDisplay().renderer;

            if (std.mem.endsWith(u8, asset_name, ".png")) {
                const image_info = loadImage(file_data) catch |err| {
                    self.logger.err("failed to load data from {s}: {s}", .{ asset.real_path, @errorName(err) });
                    return error.AssertLoadFailed;
                };

                if (image_info.data.len > 1024 * 1024 * 8) {
                    self.logger.err("image {s} is too large: {d}", .{ asset_name, image_info.data.len });
                    return error.ImageTooLarge;
                }

                const image = renderer.createImage(image_info.data, image_info.width, image_info.height);

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
        self.first_poll = false;
    }

    fn runLocalProgram(self: *Runtime, run_info: *const LocalRun) !void {
        var asset_dir = std.fs.cwd().openDir(run_info.assets, .{ .iterate = true }) catch |err| {
            self.logger.err("failed to access directory {s}: {s}", .{ run_info.assets, @errorName(err) });
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
                self.logger.err("failed to access file in directory {s}: {s}", .{ run_info.assets, @errorName(err) });
                return err;
            } orelse break;

            if (std.mem.endsWith(u8, file.name, ".png")) {
                const real_path = try std.fs.path.joinZ(path_allocator.allocator(), &.{ run_info.assets, file.name });
                try assets.append(path_allocator.allocator(), .{
                    .name = util.FixedArrayList(u8, fs_storage.max_asset_name_len).initFrom(file.name) catch unreachable,
                    .real_path = real_path,
                });
            }
        }

        try self.applyDeviceConfig(run_info.devices);
        try self.loadProgram(run_info.program, assets.items);
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

    pub fn run(self: *Runtime, local_run: ?LocalRun) !void {
        const time_of_day = @mod(std.time.milliTimestamp(), 24 * 60 * 60 * 1000);
        self.was_running = self.shouldRun(time_of_day);
        self.logger.info("initial run state: {}", .{self.was_running});

        if (local_run) |*run_info| {
            self.runLocalProgram(run_info) catch |err| {
                self.logger.err("error running local program: {s}", .{@errorName(err)});
                return;
            };
        } else {
            self.tryRunLatestProgram();
        }

        if (self.was_running) {
            for (self.devices.items) |*device| {
                device.start(self) catch |err| {
                    self.logger.err("failed to start device {s}: {s}", .{ device.id, @errorName(err) });
                    return err;
                };
            }
        }

        while (self.poll(null) != null) {
            if (self.calibrations_remaining == 0) {
                if (self.wasm_entry) |wasm_entry| {
                    _ = self.wasm.callFunction(wasm_entry, .{}) catch |err| {
                        self.logger.err("failed to run program: {s}", .{@errorName(err)});
                    };
                    self.logger.info("program finished", .{});

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
                for (self.devices.items) |*device| {
                    device.start(self) catch |err| {
                        self.logger.err("failed to start device {s}: {s}", .{ device.id, @errorName(err) });
                    };
                }
            } else {
                for (self.devices.items) |*device| {
                    device.stop(self);
                }
            }
            self.was_running = run_state;
        }

        var writer: ?std.io.Writer = if (event_buf) |buf| std.io.Writer.fixed(buf) else null;

        for (self.devices.items) |*device| {
            device.poll(if (writer) |*w| w else null, self) catch |err| {
                self.logger.err("fatal device poll error: {s}", .{@errorName(err)});
                return null;
            };
        }

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

        return if (writer) |*w| w.end else 0;
    }

    pub fn getDevice(self: *Runtime, id: []const u8) ?DeviceId {
        for (self.devices.items, 0..) |*device, i| {
            if (std.mem.eql(u8, device.id, id)) {
                return .{ .id = i };
            }
        }
        return null;
    }

    fn tempGetDisplay(self: *Runtime) *devices.DisplayDevice {
        for (self.devices.items) |*device| {
            switch (device.type) {
                .display => |*display| return display,
                else => {},
            }
        }
        unreachable;
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

        if (runtime.next_program != null) {
            return -1;
        }

        if (!runtime.was_running) {
            return -1;
        }

        runtime.wasm.extendTimeout();
        return @intCast(event_out_len);
    }

    fn wasmDropMaterial(env: *Wasm, id: u32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const display = runtime.tempGetDisplay();
        display.dropMaterial(.{ .id = id });
    }

    fn wasmCreateRenderedObject(env: *Wasm, material_id: u32) u32 {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.logger.trace("simulo_create_rendered_object({d})", .{material_id});
        const display = runtime.tempGetDisplay();
        const obj = display.addObject(.{ .id = material_id }, 0) catch |err| {
            runtime.logger.err("failed to create rendered object: {s}", .{@errorName(err)});
            return 0;
        };
        return obj.id;
    }

    fn wasmCreateRenderedObject2(env: *Wasm, material_id: u32, render_order: u32) u32 {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.logger.trace("simulo_create_rendered_object2({d}, {d})", .{ material_id, render_order });
        const display = runtime.tempGetDisplay();
        const obj = display.addObject(.{ .id = material_id }, @intCast(render_order)) catch |err| {
            runtime.logger.err("failed to create rendered object: {s}", .{@errorName(err)});
            return 0;
        };
        return obj.id;
    }

    fn wasmSetRenderedObjectMaterial(env: *Wasm, id: u32, material_id: u32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const display = runtime.tempGetDisplay();
        display.setObjectMaterial(.{ .id = id }, .{ .id = material_id }) catch |err| util.crash.oom(err);
    }

    fn wasmSetRenderedObjectTransforms(env: *Wasm, count: u32, ids: [*]u32, transforms: [*]f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.logger.trace("simulo_set_rendered_object_transforms({d}, {*}, {*})", .{ count, ids, transforms });

        const display = runtime.tempGetDisplay();
        display.setObjectsTransforms(count, ids, transforms);
    }

    fn wasmSetRenderedObjectColors(env: *Wasm, count: u32, ids: [*]u32, colors: [*]f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.logger.trace("simulo_set_rendered_object_colors({d}, {*}, {*})", .{ count, ids, colors });

        const display = runtime.tempGetDisplay();
        display.setObjectsColors(count, ids, colors);
    }

    fn wasmDropRenderedObject(env: *Wasm, id: u32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        runtime.logger.trace("simulo_drop_rendered_object({d})", .{id});
        const display = runtime.tempGetDisplay();
        display.deleteObject(.{ .id = id });
    }

    fn wasmSetCamera2d(env: *Wasm, near: f32, far: f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const display = runtime.tempGetDisplay();
        display.setCamera2d(near, far);
    }

    fn wasmSetCamera3d(env: *Wasm, fov: f32, near: f32, far: f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const display = runtime.tempGetDisplay();
        display.setCamera3d(fov, near, far);
    }

    fn wasmSetCameraOffAxis(env: *Wasm, top: f32, bottom: f32, left: f32, right: f32, near: f32, far: f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const display = runtime.tempGetDisplay();
        display.setCameraOffAxis(top, bottom, left, right, near, far);
    }

    fn wasmSetViewMatrix(env: *Wasm, matrix: [*]f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const display = runtime.tempGetDisplay();
        display.setViewMatrix(Mat4.fromColumnMajorPtr(matrix));
    }

    fn wasmCreateMaterial(env: *Wasm, name: [*c]u8, name_len: u32, r: f32, g: f32, b: f32, a: f32) u32 {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const display = runtime.tempGetDisplay();

        const image = if (!runtime.wasm.isNullptr(name)) cond: {
            const name_slice = name[0..name_len];
            runtime.logger.trace("simulo_create_material(\"{s}\", {d}, {d}, {d}, {d})", .{ name_slice, r, g, b, a });
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
            runtime.logger.trace("simulo_create_material(null, {d}, {d}, {d}, {d})", .{ r, g, b, a });
            break :cond null;
        };

        const material = display.createUiMaterial(image, r, g, b, a) catch |err| util.crash.oom(err);
        return material.id;
    }

    fn wasmUpdateMaterial(env: *Wasm, id: u32, r: f32, g: f32, b: f32, a: f32) void {
        const runtime: *Runtime = @alignCast(@fieldParentPtr("wasm", env));
        const display = runtime.tempGetDisplay();
        display.updateMaterial(.{ .id = id }, r, g, b, a);
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
