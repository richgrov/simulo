const std = @import("std");

pub const CameraDevice = @import("camera.zig").CameraDevice;
pub const DisplayDevice = @import("display.zig").DisplayDevice;
const Runtime = @import("../runtime.zig").Runtime;

pub const DeviceType = {};

pub const Device = union(enum) {
    camera: CameraDevice,
    display: DisplayDevice,

    pub fn start(self: *Device, runtime: *Runtime) !void {
        switch (self.*) {
            .camera => |*camera| try camera.start(runtime),
            .display => |*display| try display.start(runtime),
        }
    }

    pub fn stop(self: *Device, runtime: *Runtime) void {
        switch (self.*) {
            .camera => |*camera| camera.stop(runtime),
            .display => |*display| display.stop(runtime),
        }
    }

    pub fn poll(self: *Device, events: ?*std.io.Writer, runtime: *Runtime) !void {
        switch (self.*) {
            .camera => |*camera| try camera.poll(events, runtime),
            .display => |*display| try display.poll(events, runtime),
        }
    }

    pub fn deinit(self: *Device, runtime: *Runtime) void {
        switch (self.*) {
            .camera => |*camera| camera.deinit(runtime),
            .display => |*display| display.deinit(runtime),
        }
    }

    pub fn id(self: *Device) []const u8 {
        switch (self.*) {
            .camera => |*camera| return camera.id.items(),
            .display => |*display| return display.id.items(),
        }
    }
};
