const std = @import("std");

pub const LogLevel = enum {
    trace,
    debug,
    info,
    warn,
    err,
};

pub var global_log_level: LogLevel = .debug;

pub fn Logger(comptime name: []const u8, fmt_buf_size: usize) type {
    return struct {
        write_buf: [fmt_buf_size]u8 = undefined,

        const Self = @This();

        pub fn init() Self {
            return .{};
        }

        fn shouldLog(level: LogLevel) bool {
            return @intFromEnum(level) >= @intFromEnum(global_log_level);
        }

        fn log(self: *Self, comptime level: LogLevel, comptime fmt: []const u8, args: anytype) void {
            if (!shouldLog(level)) return;

            const level_str = switch (level) {
                .trace => "TRC",
                .debug => "DBG",
                .info => "INF",
                .warn => "WRN",
                .err => "ERR",
            };

            const writer = std.debug.lockStderrWriter(&.{});
            defer std.debug.unlockStdErr();

            const now: u64 = @intCast(std.time.milliTimestamp());
            const secs = now / 1000;
            const mins = secs / 60;
            const hrs = mins / 60;
            const days = hrs / 24;

            const msg = std.fmt.bufPrint(
                &self.write_buf,
                "{d:0>5} {d:0>2}:{d:0>2}:{d:0>2}.{d:0>3} " ++ level_str ++ " [" ++ name ++ "] " ++ fmt ++ "\n",
                .{ days, hrs % 24, mins % 60, secs % 60, now % 1000 } ++ args,
            ) catch {
                writer.writeAll("????? ??:??:??.??? " ++ level_str ++ " [" ++ name ++ "] <log message too long; fmt:> " ++ fmt ++ "\n") catch {};
                return;
            };
            writer.writeAll(msg) catch {};
        }

        pub fn trace(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.log(.trace, fmt, args);
        }

        pub fn debug(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.log(.debug, fmt, args);
        }

        pub fn info(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.log(.info, fmt, args);
        }

        pub fn warn(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.log(.warn, fmt, args);
        }

        pub fn err(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.log(.err, fmt, args);
        }
    };
}
