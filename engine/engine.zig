const std = @import("std");
const builtin = @import("builtin");

pub const math = @import("math/matrix.zig");

pub const midi = @import("midi.zig");

pub const profiler = @import("profiler.zig");

test {
    comptime {
        _ = midi;
    }
}
