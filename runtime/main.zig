const std = @import("std");
const builtin = @import("builtin");

const engine = @import("engine");
const util = @import("util");
const Runtime = @import("runtime.zig").Runtime;

const fs_storage = @import("fs_storage.zig");

pub fn main() !void {
    var dba = std.heap.DebugAllocator(.{}).init;
    defer {
        if (dba.deinit() == .leak) {
            std.log.err("memory leak detected", .{});
        }
    }
    const allocator = dba.allocator();

    fs_storage.globalInit(allocator) catch |err| {
        std.log.err("error: failed to initialize fs storage: {s}", .{@errorName(err)});
        return;
    };

    const machine_id = std.process.getEnvVarOwned(allocator, "SIMULO_MACHINE_ID") catch |err| {
        switch (err) {
            error.EnvironmentVariableNotFound => {
                std.log.err("error: SIMULO_MACHINE_ID is not set", .{});
                return;
            },
            error.OutOfMemory => util.crash.oom(error.OutOfMemory),
            else => {
                std.log.err("error: failed to get SIMULO_MACHINE_ID: {any}", .{err});
                return;
            },
        }
    };
    defer allocator.free(machine_id);

    try Runtime.globalInit();
    defer Runtime.globalDeinit();

    var runtime: Runtime = undefined;
    try Runtime.init(&runtime, machine_id, allocator);
    defer runtime.deinit();

    try runtime.run();
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
