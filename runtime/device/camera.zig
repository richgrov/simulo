const std = @import("std");

const Logger = @import("../log.zig").Logger;
const DisplayDevice = @import("display.zig").DisplayDevice;

const PoseDetector = @import("../inference/pose.zig").PoseDetector;
const Runtime = @import("../runtime.zig").Runtime;

pub const CameraDevice = struct {
    pose_detector: PoseDetector,
    logger: Logger("camera", 1024) = Logger("camera", 1024).init(),

    pub fn init(camera_id: []const u8, runtime: *Runtime) CameraDevice {
        _ = runtime;
        return .{ .pose_detector = PoseDetector.init(camera_id) };
    }

    pub fn start(self: *CameraDevice, runtime: *Runtime) !void {
        self.pose_detector.outputs.clear();

        for (runtime.devices.items) |*device| {
            switch (device.type) {
                .display => |*d| {
                    self.pose_detector.outputs.append(&d.camera_chan) catch |err| {
                        self.logger.err("failed to bridge camera to display: {s}", .{@errorName(err)});
                    };
                },
                else => continue,
            }
        }

        try self.pose_detector.start();
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
