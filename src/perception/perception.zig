const engine = @import("engine");
const std = @import("std");

comptime {
    _ = engine;
}

extern fn perception_test_main() void;

pub fn main() !void {
    var perception = try engine.Perception.init();
    defer perception.deinit();
    std.debug.print("Hello, world!\n", .{});
}
