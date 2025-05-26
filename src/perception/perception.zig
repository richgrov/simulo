const engine = @import("engine");
const std = @import("std");

comptime {
    _ = engine;
}

extern fn perception_test_main() void;

pub fn main() !void {
    var bframe: [480 * 640 * 3]u8 = undefined;
    var fframe: [640 * 640 * 3]f32 = undefined;
    @memset(&fframe, 114);

    var camera = try engine.Camera.init(&bframe);
    defer camera.deinit();
    camera.setFloatMode(&fframe);

    var perception = try engine.Perception.init();
    defer perception.deinit();
    std.debug.print("Hello, world!\n", .{});
}
