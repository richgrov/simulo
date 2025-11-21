const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const engine = @import("engine");
const util = @import("util");
const Runtime = @import("runtime.zig").Runtime;
const Logger = @import("log.zig").Logger;

const DeviceConfig = @import("device/config.zig").DeviceConfig;
const DevConfig = @import("dev/config.zig").DevConfig;
const fs_storage = @import("fs_storage.zig");

const ini = @import("ini.zig");

const usage = if (build_options.cloud)
    "usage: runtime"
else
    "usage: simulo dev";

pub fn main() !void {
    var args = std.process.args();
    defer args.deinit();
    std.debug.assert(args.skip());

    var dba = std.heap.DebugAllocator(.{}).init;
    defer {
        if (dba.deinit() == .leak) {
            std.debug.print("memory leak detected\n", .{});
        }
    }
    const allocator = dba.allocator();

    fs_storage.globalInit(allocator) catch |err| {
        std.debug.print("error: failed to initialize fs storage: {s}", .{@errorName(err)});
        return;
    };

    var runtime = try Runtime.init(allocator);
    defer runtime.deinit();

    if (build_options.cloud) {
        try runtime.run(null);
    } else {
        const command = args.next() orelse {
            std.debug.print(usage ++ "\n", .{});
            return;
        };

        if (!std.mem.eql(u8, command, "dev")) {
            std.debug.print(usage ++ "\n", .{});
            return;
        }

        var config_parser = ini.Iterator.init("devices.ini") catch |err| {
            std.debug.print("error: failed to create parser for devices.ini: {s}", .{@errorName(err)});
            return;
        };

        var config = DeviceConfig.init(allocator, &config_parser) catch |err| {
            std.debug.print("error: failed to parse devices.ini: {s}", .{@errorName(err)});
            return;
        };
        defer config.deinit();

        var parser = ini.Iterator.init("simulo.ini") catch |err| {
            std.debug.print("error: failed to open simulo.ini: {s}\n", .{@errorName(err)});
            return;
        };

        const dev_config = DevConfig.init(&parser) catch |err| {
            std.debug.print("error: failed to parse simulo.ini: {s}\n", .{@errorName(err)});
            return;
        };

        try runtime.run(.{ .program = dev_config.program_path, .assets = dev_config.assets_dir, .devices = &config });
    }
}

const vulkan = builtin.target.os.tag == .windows or builtin.target.os.tag == .linux;
const text_vert = if (vulkan) @embedFile("shader/text.vert.spv") else &[_]u8{0};
const text_frag = if (vulkan) @embedFile("shader/text.frag.spv") else &[_]u8{0};
const model_vert = if (vulkan) @embedFile("shader/model.vert.spv") else &[_]u8{0};
const model_frag = if (vulkan) @embedFile("shader/model.frag.spv") else &[_]u8{0};
const arial = @embedFile("res/arial.ttf");

test {
    comptime {
        _ = ini;
    }
}

pub export fn text_vertex_bytes() *const u8 {
    return &text_vert[0];
}

pub export fn text_vertex_len() usize {
    return text_vert.len;
}

pub export fn text_fragment_bytes() *const u8 {
    return &text_frag[0];
}

pub export fn text_fragment_len() usize {
    return text_frag.len;
}

pub export fn model_vertex_bytes() *const u8 {
    return &model_vert[0];
}

pub export fn model_vertex_len() usize {
    return model_vert.len;
}

pub export fn model_fragment_bytes() *const u8 {
    return &model_frag[0];
}

pub export fn model_fragment_len() usize {
    return model_frag.len;
}

pub export fn arial_bytes() *const u8 {
    return &arial[0];
}

pub export fn arial_len() usize {
    return arial.len;
}
