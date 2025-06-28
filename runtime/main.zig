const std = @import("std");
const builtin = @import("builtin");

const engine = @import("engine");
const Runtime = @import("runtime.zig").Runtime;

fn printUsage() void {
    std.log.err("Usage: simulo <private_key_path> <machine_id> <program_url>", .{});
}

fn readPrivateKey(path: []const u8) ![32]u8 {
    var private_key_buf: [68]u8 = undefined;
    const private_key_der = try std.fs.cwd().readFile(path, &private_key_buf);
    if (private_key_der.len < 48) {
        return error.PrivateKeyTooShort;
    }

    var private_key: [32]u8 = undefined;
    @memcpy(&private_key, private_key_der[private_key_der.len - 32 ..]);
    return private_key;
}

pub fn main() !void {
    var dba = std.heap.DebugAllocator(.{}).init;
    defer {
        if (dba.deinit() == .leak) {
            std.log.err("memory leak detected", .{});
        }
    }
    const allocator = dba.allocator();

    var args = std.process.args();
    defer args.deinit();

    _ = args.next(); // skip program name

    const private_key_path = args.next() orelse {
        printUsage();
        return;
    };
    const private_key = readPrivateKey(private_key_path) catch |err| {
        std.log.err("failed to read private key: {any}", .{err});
        return;
    };

    const machine_id = args.next() orelse {
        printUsage();
        return;
    };

    try Runtime.globalInit();
    defer Runtime.globalDeinit();

    var runtime: Runtime = undefined;
    try Runtime.init(&runtime, machine_id, &private_key, allocator);
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
