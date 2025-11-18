const std = @import("std");

const IniIterator = @import("../ini.zig").Iterator;

pub const DevConfig = struct {
    project_id: i32,
    program_path: []const u8,
    assets_dir: []const u8,

    const Self = @This();

    pub fn init(ini: *IniIterator) !Self {
        var project_id: ?i32 = null;
        var program_path: ?[]const u8 = null;
        var assets_dir: ?[]const u8 = null;

        while (try ini.next()) |event| {
            switch (event) {
                .pair => |pair| {
                    if (std.mem.eql(u8, pair.key, "project_id")) {
                        project_id = try std.fmt.parseInt(i32, pair.value, 10);
                    } else if (std.mem.eql(u8, pair.key, "program_path")) {
                        program_path = pair.value;
                    } else if (std.mem.eql(u8, pair.key, "assets_dir")) {
                        assets_dir = pair.value;
                    } else {
                        return error.UnexpectedKey;
                    }
                },
                .section => |_| {
                    return error.UnexpectedSection;
                },
                .err => |_| {
                    return error.ConfigParseError;
                },
            }
        }

        return Self{
            .project_id = project_id orelse return error.MissingProjectId,
            .program_path = program_path orelse return error.MissingProgramPath,
            .assets_dir = assets_dir orelse return error.MissingAssetsDir,
        };
    }
};

