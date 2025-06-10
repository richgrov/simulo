const std = @import("std");

const Runtime = @import("runtime.zig").Runtime;

pub fn main() !void {
    var dba = std.heap.DebugAllocator(.{}).init;
    defer {
        if (dba.deinit() == .leak) {
            std.log.err("memory leak detected", .{});
        }
    }
    const allocator = dba.allocator();

    var runtime: Runtime = undefined;
    try Runtime.init(&runtime, allocator);
    defer runtime.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // skip program name
    const script_path = args.next() orelse {
        std.log.err("provide a path to a script", .{});
        return;
    };

    const script_file = std.fs.cwd().readFileAlloc(allocator, script_path, std.math.maxInt(usize)) catch |err| {
        std.log.err("failed to read script file: {}", .{err});
        return;
    };
    defer allocator.free(script_file);

    try runtime.runScript(script_file, script_path);
    try runtime.run();
}
