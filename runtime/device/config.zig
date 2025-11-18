const std = @import("std");

const util = @import("util");

const IniIterator = @import("../ini.zig").Iterator;

pub const DeviceConfig = struct {
    devices: std.StringArrayHashMap(Device),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, ini: *IniIterator) !DeviceConfig {
        const DeviceBuilder = union(enum) {
            projector: struct {
                display_name: ?[]const u8 = null,
                port_path: ?[]const u8 = null,
                skip_calibration: bool = false,
            },
            camera: struct {
                port_path: ?[]const u8 = null,
            },
            section: void,
            none: void,
        };

        var next_device: DeviceBuilder = .none;
        var name: ?[]const u8 = null;
        var devices = std.StringArrayHashMap(Device).init(allocator);

        while (try ini.next()) |event| {
            switch (event) {
                .section => |title| {
                    switch (next_device) {
                        .projector => |*projector| {
                            const device_name = name orelse return error.MissingDeviceName;
                            const display_name = projector.display_name orelse return error.MissingDisplayName;

                            try devices.put(device_name, .{ .projector = .{
                                .display_name = display_name,
                                .port_path = projector.port_path,
                                .skip_calibration = projector.skip_calibration,
                            } });
                        },
                        .camera => |*camera| {
                            const device_name = name orelse return error.MissingDeviceName;
                            const port_path = camera.port_path orelse return error.MissingPortPath;
                            try devices.put(device_name, .{ .camera = .{ .port_path = port_path } });
                        },
                        .section => return error.IncompleteDevice,
                        .none => {},
                    }
                    next_device = .none;

                    if (!std.mem.eql(u8, title, "device")) {
                        return error.InvalidSection;
                    }
                    next_device = DeviceBuilder.section;
                },
                .pair => |pair| {
                    switch (next_device) {
                        .section => {
                            if (!std.mem.eql(u8, pair.key, "type")) {
                                return error.ExpectedDeviceType;
                            }

                            if (std.mem.eql(u8, pair.value, "projector")) {
                                next_device = .{ .projector = .{} };
                            } else if (std.mem.eql(u8, pair.value, "camera")) {
                                next_device = .{ .camera = .{} };
                            }
                        },
                        .projector => |*projector| {
                            if (std.mem.eql(u8, pair.key, "display_name")) {
                                projector.display_name = pair.value;
                            } else if (std.mem.eql(u8, pair.key, "port_path")) {
                                projector.port_path = pair.value;
                            } else if (std.mem.eql(u8, pair.key, "skip_calibration")) {
                                if (std.mem.eql(u8, pair.value, "true")) {
                                    projector.skip_calibration = true;
                                } else if (std.mem.eql(u8, pair.value, "false")) {
                                    projector.skip_calibration = false;
                                } else {
                                    return error.ExpectedBool;
                                }
                            } else if (std.mem.eql(u8, pair.key, "name")) {
                                name = pair.value;
                            } else {
                                return error.UnexpectedValue;
                            }
                        },
                        .camera => |*camera| {
                            if (std.mem.eql(u8, pair.key, "port_path")) {
                                camera.port_path = pair.value;
                            } else if (std.mem.eql(u8, pair.key, "name")) {
                                name = pair.value;
                            } else {
                                return error.UnexpectedValue;
                            }
                        },
                        .none => return error.ValueOutsideDeviceSection,
                    }
                },
                .err => |_| {
                    return error.ConfigParseError;
                },
            }
        }

        switch (next_device) {
            .projector => |*projector| {
                const device_name = name orelse return error.MissingDeviceName;
                const display_name = projector.display_name orelse return error.MissingDisplayName;

                try devices.put(device_name, .{ .projector = .{
                    .display_name = display_name,
                    .port_path = projector.port_path,
                    .skip_calibration = projector.skip_calibration,
                } });
            },
            .camera => |*camera| {
                const device_name = name orelse return error.MissingDeviceName;
                const port_path = camera.port_path orelse return error.MissingPortPath;
                try devices.put(device_name, .{ .camera = .{ .port_path = port_path } });
            },
            .section => return error.IncompleteDevice,
            .none => {},
        }

        return .{
            .devices = devices,
        };
    }

    pub fn deinit(self: *Self) void {
        self.devices.deinit();
    }

    pub fn save(self: *const Self, writer: *std.io.Writer) !void {
        const formatter = std.json.fmt(self, .{
            .emit_null_optional_fields = false,
        });
        try formatter.format(writer);
    }
};

pub const Device = union(enum) {
    projector: struct {
        display_name: []const u8,
        port_path: ?[]const u8,
        skip_calibration: bool = false,
    },
    camera: struct {
        port_path: []const u8,
    },
};
