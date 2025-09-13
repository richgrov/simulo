const std = @import("std");

pub fn Logger(comptime name: []const u8, fmt_buf_size: usize) type {
    return struct {
        write_buf: [fmt_buf_size]u8 = undefined,

        const Self = @This();

        pub fn init() Self {
            return .{};
        }

        fn log(self: *Self, comptime fmt: []const u8, args: anytype) void {
            const writer = std.debug.lockStderrWriter(&.{});
            defer std.debug.unlockStdErr();

            const msg = std.fmt.bufPrint(&self.write_buf, "{d} " ++ name ++ " " ++ fmt ++ "\n", .{std.time.milliTimestamp()} ++ args) catch {
                writer.writeAll("<log message too long>\n") catch {};
                return;
            };
            writer.writeAll(msg) catch {};
        }

        pub fn trace(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.log("TRC " ++ fmt, args);
        }

        pub fn debug(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.log("DBG " ++ fmt, args);
        }

        pub fn info(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.log("INF " ++ fmt, args);
        }

        pub fn warn(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.log("WRN " ++ fmt, args);
        }

        pub fn err(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.log("ERR " ++ fmt, args);
        }
    };
}
