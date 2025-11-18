const std = @import("std");

pub const CameraDevice = @import("camera.zig").CameraDevice;
pub const DisplayDevice = @import("display.zig").DisplayDevice;
const Runtime = @import("../runtime.zig").Runtime;

pub const DeviceType = union(enum) {
    camera: CameraDevice,
    display: DisplayDevice,
};

pub const Device = struct {
    id: []const u8,
    type: DeviceType,

    pub fn init(id: []const u8, ty: DeviceType) Device {
        return .{ .id = id, .type = ty };
    }

    pub fn start(self: *Device, runtime: *Runtime) !void {
        switch (self.type) {
            .camera => |*camera| try camera.start(runtime),
            .display => |*display| try display.start(runtime),
        }
    }

    pub fn stop(self: *Device, runtime: *Runtime) void {
        switch (self.type) {
            .camera => |*camera| camera.stop(runtime),
            .display => |*display| display.stop(runtime),
        }
    }

    pub fn poll(self: *Device, events: ?*std.io.Writer, runtime: *Runtime) !void {
        switch (self.type) {
            .camera => |*camera| try camera.poll(events, runtime),
            .display => |*display| try display.poll(events, runtime),
        }
    }

    pub fn deinit(self: *Device, runtime: *Runtime) void {
        switch (self.type) {
            .camera => |*camera| camera.deinit(runtime),
            .display => |*display| display.deinit(runtime),
        }
    }
};
