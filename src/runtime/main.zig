const std = @import("std");

const engine = @import("engine");
const Runtime = @import("runtime.zig").Runtime;

pub fn main() !void {
    var dba = std.heap.DebugAllocator(.{}).init;
    defer {
        if (dba.deinit() == .leak) {
            std.log.err("memory leak detected", .{});
        }
    }
    const allocator = dba.allocator();

    try Runtime.globalInit();
    defer Runtime.globalDeinit();

    var runtime: Runtime = undefined;
    try Runtime.init(&runtime, allocator);
    defer runtime.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // skip program name
    const program_url = args.next() orelse {
        std.log.err("provide a path to a script", .{});
        return;
    };

    try runtime.runProgram(program_url);
    try runtime.run();
}
