const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const engine = @import("engine");
const util = @import("util");
const Runtime = @import("runtime.zig").Runtime;
const Logger = @import("log.zig").Logger;

const fs_storage = @import("fs_storage.zig");

pub fn main() !void {
    var arg_buf: [128]u8 = undefined;
    var arg_allocator = std.heap.FixedBufferAllocator.init(&arg_buf);
    var args = std.process.argsWithAllocator(arg_allocator.allocator()) catch |err| {
        std.debug.print("failed to read program args", .{@errorName(err)});
        return;
    };
    defer args.deinit();

    var logger = Logger("init", 1024).init();
    const local_asset_path = if (build_options.cloud) blk: {
        logger.info("simulo runtime (git: {s}, api: {s})", .{
            build_options.git_hash,
            build_options.api_url,
        });
        break :blk null;
    } else blk: {
        logger.info("simulo runtime (git: {s})", .{build_options.git_hash});

        std.debug.assert(args.skip());
        break :blk args.next() orelse {
            logger.err("provide a path to a directory containing main.wasm and assets", .{});
            return;
        };
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

    var runtime: Runtime = undefined;
    try Runtime.init(&runtime, allocator);
    defer runtime.deinit();

    try runtime.run(local_asset_path);
}

const vulkan = builtin.target.os.tag == .windows or builtin.target.os.tag == .linux;
const text_vert = if (vulkan) @embedFile("shader/text.vert.spv") else &[_]u8{0};
const text_frag = if (vulkan) @embedFile("shader/text.frag.spv") else &[_]u8{0};
const model_vert = if (vulkan) @embedFile("shader/model.vert.spv") else &[_]u8{0};
const model_frag = if (vulkan) @embedFile("shader/model.frag.spv") else &[_]u8{0};
const arial = @embedFile("res/arial.ttf");

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
