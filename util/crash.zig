const std = @import("std");

pub fn oom(_: error{OutOfMemory}) noreturn {
    std.debug.dumpCurrentStackTrace(null);
    std.debug.panic("simulo ran out of memory. Additional information is above.\n", .{});
}
