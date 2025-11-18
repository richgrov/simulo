const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const engine = @import("engine");
const util = @import("util");
const Runtime = @import("runtime.zig").Runtime;
const Logger = @import("log.zig").Logger;

const DeviceConfig = @import("device/config.zig").DeviceConfig;
const fs_storage = @import("fs_storage.zig");

const ini = @import("ini.zig");

const usage = if (build_options.cloud)
    "usage: runtime"
else
    "usage: runtime <program path> <asset path>";

pub fn main() !void {
    var arg_buf: [128]u8 = undefined;
    var arg_allocator = std.heap.FixedBufferAllocator.init(&arg_buf);
    var args = std.process.argsWithAllocator(arg_allocator.allocator()) catch |err| {
        std.debug.print("failed to read program args: {s}\n", .{@errorName(err)});
        return;
    };
    defer args.deinit();

    var logger = Logger("init", 1024).init();

    std.debug.assert(args.skip());

    const local_program_path, const local_asset_path = if (build_options.cloud) blk: {
        logger.info("simulo runtime (git: {s}, api: {s})", .{
            build_options.git_hash,
            build_options.api_url,
        });
        break :blk .{ null, null };
    } else blk: {
        logger.info("simulo runtime (git: {s})", .{build_options.git_hash});

        const program = args.next() orelse {
            std.debug.print(usage ++ "\n", .{});
            return;
        };

        const assets = args.next() orelse {
            std.debug.print(usage ++ "\n", .{});
            return;
        };

        break :blk .{ program, assets };
    };

    var dba = std.heap.DebugAllocator(.{}).init;
    defer {
        if (dba.deinit() == .leak) {
            logger.err("memory leak detected", .{});
        }
    }
    const allocator = dba.allocator();

    fs_storage.globalInit(allocator) catch |err| {
        logger.err("error: failed to initialize fs storage: {s}", .{@errorName(err)});
        return;
    };

    var config_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const config_path = fs_storage.getFilePath(&config_path_buf, "devices.ini") catch |err| {
        logger.err("error: failed to get config path: {s}", .{@errorName(err)});
        return;
    };

    var config_buf: [1024 * 2]u8 = undefined;
    const config_data = std.fs.cwd().readFile(config_path, &config_buf) catch |err| {
        logger.err("error: failed to read config file: {s}", .{@errorName(err)});
        return;
    };

    var parser = ini.Iterator.init(config_data) catch |err| {
        logger.err("error: failed to create config parser: {s}", .{@errorName(err)});
        return;
    };

    var config = DeviceConfig.init(allocator, &parser) catch |err| {
        logger.err("error: failed to parse config: {s}", .{@errorName(err)});
        return;
    };
    defer config.deinit();

    var runtime: Runtime = undefined;
    try Runtime.init(&runtime, allocator);
    defer runtime.deinit();

    try runtime.run(.{ .program = local_program_path, .assets = local_asset_path, .devices = &config });
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
