const std = @import("std");

const engine = @import("engine");
const math = engine.math;
const util = @import("util");
const DMat3 = math.DMat3;
const Mat4 = math.Mat4;

const Renderer = @import("../render/renderer.zig").Renderer;
const Runtime = @import("../runtime.zig").Runtime;
const Window = @import("../window/window.zig").Window;
const Gpu = @import("../gpu/gpu.zig").Gpu;
const Serial = @import("../serial/serial.zig").Serial;

const EyeGuard = @import("../eyeguard.zig").EyeGuard;
const Logger = @import("../log.zig").Logger;
const IniIterator = @import("../ini.zig").Iterator;

const wasm_message = @import("../wasm_message.zig");

const Profiler = engine.profiler.Profiler;

const DisplayProfiler = Profiler("display", enum {
    setup_frame,
    poll_window,
    resize,
    process_pose,
    update,
    render,
});

const FIRST_PROGRAM_VISIBLE_RENDER_LAYER = 8;
const MAX_PROGRAM_VISIBLE_RENDER_LAYERS = 16;

const poses = @import("../inference/pose.zig");

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

const power_on = [_]u8{ 0x06, 0x14, 0x00, 0x04, 0x00, 0x34, 0x11, 0x00, 0x00, 0x5D };
const power_off = [_]u8{ 0x06, 0x14, 0x00, 0x04, 0x00, 0x34, 0x11, 0x01, 0x00, 0x5E };

pub const DisplayDevice = struct {
    id: util.FixedArrayList(u8, 16),
    allocator: std.mem.Allocator,

    last_width: i32,
    last_height: i32,
    gpu: *Gpu,
    window: Window,
    renderer: Renderer,
    serial: ?Serial,

    logger: Logger("display", 1024),
    poll_profiler: DisplayProfiler,
    was_running: bool = false,
    view: Mat4,
    projection: union(enum) {
        d2: struct { near: f32, far: f32 },
        d3: struct { near: f32, far: f32, fov: f32 },
        off_axis: struct { top: f32, bottom: f32, left: f32, right: f32, near: f32, far: f32 },
    },
    eyeguard: EyeGuard,
    quad_mesh: Renderer.MeshHandle,
    white_pixel_texture: Renderer.ImageHandle,
    chessboard: Renderer.ObjectHandle,
    calibration_state: union(enum) {
        capturing_background,
        capturing_chessboard,
        calibrated: DMat3,
    },

    camera_chan: poses.DetectionSpsc,

    pub fn createFromIni(allocator: std.mem.Allocator, ini: *IniIterator) !DisplayDevice {
        var name: ?[]const u8 = null;
        var port_path: ?[]const u8 = null;
        var skip_calibration = false;

        while (try ini.nextProperty()) |event| {
            switch (event) {
                .pair => |pair| {
                    if (std.mem.eql(u8, pair.key, "name")) {
                        name = pair.value;
                    } else if (std.mem.eql(u8, pair.key, "port_path")) {
                        port_path = pair.value;
                    } else if (std.mem.eql(u8, pair.key, "skip_calibration")) {
                        skip_calibration = try pair.valueAsBool();
                    }
                },
                .err => return error.ConfigParseError,
            }
        }

        return DisplayDevice.init(
            allocator,
            name orelse return error.MissingDeviceName,
            if (skip_calibration) DMat3.fromRowMajorPtr(
                0.003465738042295429,
                0.00036398162088034246,
                -0.7055546341447464,
                3.695970456063997e-05,
                0.006264669923028584,
                -1.3535937399766214,
                -1.8032730687712297e-05,
                0.0008616631598779344,
                1.0,
            ) else null,
            if (port_path) |p| @ptrCast(p) else null,
        );
    }

    pub fn init(allocator: std.mem.Allocator, id: []const u8, transform_override: ?DMat3, serial_port: ?[:0]const u8) !DisplayDevice {
        const gpu = try allocator.create(Gpu);
        gpu.* = Gpu.init();
        errdefer gpu.deinit(); // TODO: this causes a segfault
        errdefer allocator.destroy(gpu);

        var window = Window.init(gpu, "simulo runtime");
        errdefer window.deinit();

        var renderer = try Renderer.init(gpu, &window, allocator);
        errdefer renderer.deinit();

        const image = createChessboard(&renderer);
        const white_pixel_texture = renderer.createImage(&[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF }, 1, 1);
        const chessboard_material = try renderer.createUiMaterial(image, 1.0, 1.0, 1.0, 1.0);
        const mesh = try renderer.createMesh(std.mem.asBytes(&vertices), &[_]u16{ 0, 1, 2, 2, 3, 0 });

        const chessboard = try renderer.addObject(mesh, Mat4.identity(), chessboard_material, 31);
        errdefer renderer.deleteObject(chessboard);

        var eyeguard = try EyeGuard.init(allocator, &renderer, mesh, white_pixel_texture);
        errdefer eyeguard.deinit();

        var serial = if (serial_port) |ser_port| Serial.open(ser_port, 1000) catch return error.OpenDisplaySerialFailed else null;
        errdefer if (serial) |*ser| ser.close();

        return DisplayDevice{
            .id = util.FixedArrayList(u8, 16).initFrom(id) catch return error.DisplayIdTooLong,
            .allocator = allocator,

            .last_width = 0,
            .last_height = 0,
            .gpu = gpu,
            .window = window,
            .renderer = renderer,
            .serial = serial,

            .logger = Logger("display", 1024).init(),
            .poll_profiler = DisplayProfiler.init(),
            .view = Mat4.identity(),
            .projection = .{ .d2 = .{ .near = -1.0, .far = 1.0 } },
            .quad_mesh = mesh,
            .white_pixel_texture = white_pixel_texture,
            .eyeguard = eyeguard,
            .chessboard = chessboard,
            .calibration_state = if (transform_override) |transform| .{ .calibrated = transform } else .capturing_background,

            .camera_chan = poses.DetectionSpsc.init(),
        };
    }

    pub fn start(self: *DisplayDevice, runtime: *Runtime) !void {
        _ = runtime;

        if (self.serial) |*serial| {
            serial.writeAll(&power_on) catch |err| {
                self.logger.err("failed to send power-on command to projector- must be done manually: {s}", .{@errorName(err)});
            };
        }
    }

    pub fn stop(self: *DisplayDevice, runtime: *Runtime) void {
        _ = runtime;

        if (self.serial) |*serial| {
            serial.writeAll(&power_off) catch |err| {
                self.logger.err("failed to send power-off command to projector- must be done manually: {s}", .{@errorName(err)});
            };
        }

        for (FIRST_PROGRAM_VISIBLE_RENDER_LAYER..FIRST_PROGRAM_VISIBLE_RENDER_LAYER + MAX_PROGRAM_VISIBLE_RENDER_LAYERS) |layer| {
            self.renderer.clearLayer(@intCast(layer));
        }
        self.renderer.clearUiMaterials();
    }

    pub fn poll(self: *DisplayDevice, events: ?*std.io.Writer, runtime: *Runtime) !void {
        self.poll_profiler.reset();

        const width = self.window.getWidth();
        const height = self.window.getHeight();

        const running = events != null;
        const run_state_changed = running != self.was_running;
        if (events) |w| {
            if (run_state_changed) {
                wasm_message.writeResizeEvent(w, @intCast(width), @intCast(height)) catch |err| {
                    self.logger.err("failed to write resize event: {s}", .{@errorName(err)});
                };
            }
        } else if (run_state_changed) {
            for (FIRST_PROGRAM_VISIBLE_RENDER_LAYER..FIRST_PROGRAM_VISIBLE_RENDER_LAYER + MAX_PROGRAM_VISIBLE_RENDER_LAYERS) |layer| {
                self.renderer.clearLayer(@intCast(layer));
            }
            self.renderer.clearUiMaterials();
        }
        self.was_running = running;

        self.poll_profiler.log(.setup_frame);

        if (!self.window.poll()) {
            return error.WindowClosed;
        }

        self.poll_profiler.log(.poll_window);

        if (width != self.last_width or height != self.last_height) {
            self.last_width = width;
            self.last_height = height;

            if (events) |w| {
                wasm_message.writeResizeEvent(w, @intCast(width), @intCast(height)) catch |err| {
                    self.logger.err("failed to write resize event: {s}", .{@errorName(err)});
                };
            }

            if (comptime util.vulkan) {
                self.renderer.handleResize(width, height, self.window.surface());
            }

            self.renderer.setObjectTransform(
                self.chessboard,
                if (runtime.calibrations_remaining > 0)
                    Mat4.scale(.{ @floatFromInt(width), @floatFromInt(height), 1 })
                else
                    Mat4.zero(),
            );

            self.poll_profiler.log(.resize);
        }

        try self.processPoseDetections(events, runtime);
        self.poll_profiler.log(.process_pose);

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

    pub fn deinit(self: *DisplayDevice, runtime: *Runtime) void {
        _ = runtime;
        self.eyeguard.deinit();
        self.window.deinit();
        self.renderer.deinit();
        self.gpu.deinit();
        self.allocator.destroy(self.gpu);
    }

    pub fn addObject(self: *DisplayDevice, material_id: Renderer.MaterialHandle, render_order: u8) !Renderer.ObjectHandle {
        if (render_order >= MAX_PROGRAM_VISIBLE_RENDER_LAYERS) {
            self.logger.err("tried to create rendered object with render order {d}", .{render_order});
            return error.InvalidRenderOrder;
        }

        return try self.renderer.addObject(
            self.quad_mesh,
            Mat4.identity(),
            material_id,
            FIRST_PROGRAM_VISIBLE_RENDER_LAYER + @as(u8, @intCast(render_order)),
        );
    }

    pub fn dropMaterial(self: *DisplayDevice, material_id: Renderer.MaterialHandle) void {
        self.renderer.unrefMaterial(material_id.id);
    }

    pub fn setObjectMaterial(self: *DisplayDevice, object: Renderer.ObjectHandle, material: Renderer.MaterialHandle) !void {
        try self.renderer.setObjectMaterial(object, material);
    }

    pub fn setObjectTransform(self: *DisplayDevice, object: Renderer.ObjectHandle, transform: Mat4) void {
        self.renderer.setObjectTransform(object, transform);
    }

    pub fn setObjectColor(self: *DisplayDevice, object: Renderer.ObjectHandle, color: @Vector(4, f32)) void {
        self.renderer.setObjectColor(object, color);
    }

    pub fn deleteObject(self: *DisplayDevice, object: Renderer.ObjectHandle) void {
        self.renderer.deleteObject(object);
    }

    pub fn setCamera2d(self: *DisplayDevice, near: f32, far: f32) void {
        self.projection = .{ .d2 = .{ .near = near, .far = far } };
    }

    pub fn setCamera3d(self: *DisplayDevice, fov: f32, near: f32, far: f32) void {
        self.projection = .{ .d3 = .{ .fov = fov, .near = near, .far = far } };
    }

    pub fn setCameraOffAxis(self: *DisplayDevice, top: f32, bottom: f32, left: f32, right: f32, near: f32, far: f32) void {
        self.projection = .{ .off_axis = .{ .top = top, .bottom = bottom, .left = left, .right = right, .near = near, .far = far } };
    }

    pub fn setViewMatrix(self: *DisplayDevice, view: Mat4) void {
        self.view = view;
    }

    pub fn createUiMaterial(self: *DisplayDevice, image: ?Renderer.ImageHandle, r: f32, g: f32, b: f32, a: f32) !Renderer.MaterialHandle {
        const img = image orelse self.white_pixel_texture;
        return try self.renderer.createUiMaterial(img, r, g, b, a);
    }

    pub fn updateMaterial(self: *DisplayDevice, material: Renderer.MaterialHandle, r: f32, g: f32, b: f32, a: f32) void {
        self.renderer.updateMaterial(material, r, g, b, a);
    }

    pub fn setObjectsTransforms(self: *DisplayDevice, count: u32, ids: [*]u32, transforms: [*]f32) void {
        for (0..count) |i| {
            const mat = Mat4.fromColumnMajorPtr(@ptrCast(&transforms[i * 16]));
            self.renderer.setObjectTransform(.{ .id = ids[i] }, mat);
        }
    }

    pub fn setObjectsColors(self: *DisplayDevice, count: u32, ids: [*]u32, colors: [*]f32) void {
        for (0..count) |i| {
            const color = @Vector(4, f32){
                colors[i * 4 + 0],
                colors[i * 4 + 1],
                colors[i * 4 + 2],
                colors[i * 4 + 3],
            };
            self.renderer.setObjectColor(.{ .id = ids[i] }, color);
        }
    }

    fn processPoseDetections(self: *DisplayDevice, writer: ?*std.io.Writer, runtime: *Runtime) !void {
        const width: f32 = @floatFromInt(self.last_width);
        const height: f32 = @floatFromInt(self.last_height);

        while (self.camera_chan.tryDequeue()) |event| {
            switch (event) {
                .ready_to_calibrate => {
                    self.logger.info("capturing chessboard", .{});
                    self.calibration_state = .capturing_chessboard;
                    self.renderer.setObjectTransform(self.chessboard, Mat4.scale(.{ width, height, 1 }));
                },
                .calibrated => |transform| {
                    if (self.calibration_state != .capturing_chessboard) return;

                    self.calibration_state = .{ .calibrated = transform };
                    self.renderer.setObjectTransform(self.chessboard, Mat4.zero());
                    runtime.calibrations_remaining -= 1;
                },
                .move => |move| {
                    const transform = switch (self.calibration_state) {
                        .calibrated => |t| t,
                        else => {
                            self.logger.warn("got move event while calibration state was {s}", .{@tagName(self.calibration_state)});
                            continue;
                        },
                    };

                    self.eyeguard.handleEvent(move.id, &move.detection, &self.renderer, width, height);

                    var det = move.detection;
                    const transformed_pos = perspective_transform(det.box.pos[0], det.box.pos[1], &transform);
                    det.box.pos = .{ transformed_pos[0], 1 - transformed_pos[1] };
                    det.box.size = perspective_transform(det.box.size[0], det.box.size[1], &transform);

                    for (0..det.keypoints.len) |k| {
                        const kp = det.keypoints[k];
                        const transformed_kp_pos = perspective_transform(kp.pos[0], kp.pos[1], &transform);
                        const kp_pos = .{ transformed_kp_pos[0], 1 - transformed_kp_pos[1] };
                        det.keypoints[k].pos = kp_pos;
                        det.keypoints[k].score = @floatCast(kp.score);
                    }

                    if (writer) |w| {
                        wasm_message.writeMoveEvent(w, move.id, &det, width, height) catch |err| {
                            self.logger.err("failed to write move event: {s}", .{@errorName(err)});
                        };
                    }
                },
                .lost => |id| {
                    self.eyeguard.handleDelete(&self.renderer, id);

                    if (writer) |w| {
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

fn perspective_transform(x: f32, y: f32, transform: *const DMat3) @Vector(2, f32) {
    const real_y = (y - (640 - 480) / 2);
    const res = transform.vecmul(.{ @floatCast(x), @floatCast(real_y), 1 });
    return @Vector(2, f32){ @floatCast(res[0] / res[2]), @floatCast(res[1] / res[2]) };
}
