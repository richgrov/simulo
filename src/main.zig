const builtin = @import("builtin");

const migration = @cImport({
    @cInclude("ffi.h");
});

const yolo11n_pose = @embedFile("perception/yolo11n-pose.onnx");
const vulkan = builtin.target.os.tag != .windows and builtin.target.os.tag != .linux;
const text_vert = if (vulkan) @embedFile("shader/text.vert") else 0;
const text_frag = if (vulkan) @embedFile("shader/text.frag") else 0;
const model_vert = if (vulkan) @embedFile("shader/model.vert") else 0;
const model_frag = if (vulkan) @embedFile("shader/model.frag") else 0;

pub export fn pose_model_bytes() *const u8 {
    return &yolo11n_pose[0];
}

pub export fn pose_model_len() usize {
    return yolo11n_pose.len;
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

pub fn main() !void {
    migration.run();
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "use other module" {
    try std.testing.expectEqual(@as(i32, 150), lib.add(100, 50));
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("engine_lib");
