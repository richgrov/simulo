const std = @import("std");

const util = @import("util");

const Logger = @import("../log.zig").Logger;
const DisplayDevice = @import("display.zig").DisplayDevice;
const IniIterator = @import("../ini.zig").Iterator;

const PoseDetector = @import("../inference/pose.zig").PoseDetector;
const Runtime = @import("../runtime.zig").Runtime;

pub const CameraDevice = struct {
    id: util.FixedArrayList(u8, 16),
    pose_detector: PoseDetector,
    logger: Logger("camera", 1024) = Logger("camera", 1024).init(),

    pub fn createFromIni(ini: *IniIterator) !CameraDevice {
        var name: ?[]const u8 = null;
        var port_path: ?[]const u8 = null;

        while (try ini.nextProperty()) |event| {
            switch (event) {
                .pair => |pair| {
                    if (std.mem.eql(u8, pair.key, "name")) {
                        name = pair.value;
                    } else if (std.mem.eql(u8, pair.key, "port_path")) {
                        port_path = pair.value;
                    }
                },
                .err => return error.ConfigParseError,
            }
        }

        return CameraDevice.init(
            name orelse return error.MissingDeviceName,
            port_path orelse return error.MissingPortPath,
        );
    }

    pub fn init(id: []const u8, camera_id: []const u8) !CameraDevice {
        return .{
            .id = util.FixedArrayList(u8, 16).initFrom(id) catch return error.CameraIdTooLong,
            .pose_detector = try PoseDetector.init(camera_id),
        };
    }

    pub fn start(self: *CameraDevice, runtime: *Runtime) !void {
        self.pose_detector.outputs.clear();

        for (runtime.devices.items) |*device| {
            switch (device.*) {
                .display => |*d| {
                    self.pose_detector.outputs.append(&d.camera_chan) catch |err| {
                        self.logger.err("failed to bridge camera to display: {s}", .{@errorName(err)});
                    };
                },
                else => continue,
            }
        }

        try self.pose_detector.start(runtime.calibrations_remaining > 0);
    }

    pub fn stop(self: *CameraDevice, runtime: *Runtime) void {
        _ = runtime;
        self.pose_detector.stop();
    }

    pub fn poll(self: *CameraDevice, events: ?*std.io.Writer, runtime: *Runtime) !void {
        _ = self;
        _ = events;
        _ = runtime;
    }

    pub fn deinit(self: *CameraDevice, runtime: *Runtime) void {
        _ = runtime;
        self.pose_detector.stop();
    }
};
