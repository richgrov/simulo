const engine = @import("engine");
const std = @import("std");

comptime {
    _ = engine;
}

extern fn perception_test_main() void;

pub fn main() void {
    perception_test_main();
}
