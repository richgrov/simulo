const std = @import("std");
const builtin = @import("builtin");

pub const LogLevel = enum {
    trace,
    debug,
    info,
    warn,
    err,
};

pub var global_log_level: LogLevel = .debug;

pub fn Logger(comptime name: []const u8, log_buf_size: usize) type {
    return struct {
        write_buf: [log_buf_size]u8 = undefined,

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

            var writer = std.fs.File.stderr().writer(&self.write_buf);

            const now: u64 = @intCast(std.time.milliTimestamp());
            const secs = now / 1000;
            const mins = secs / 60;
            const hrs = mins / 60;
            const days = hrs / 24;

            const date = daysToDate(days);

            writer.interface.print(
                "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}.{d:0>3} " ++ level_str ++ " [" ++ name ++ "] " ++ fmt ++ "\n",
                .{ date.year, date.month, date.day, hrs % 24, mins % 60, secs % 60, now % 1000 } ++ args,
            ) catch {
                writer.interface.writeAll("????-??-?? ??:??:??.??? " ++ level_str ++ " [" ++ name ++ "] <failed to log message:> " ++ fmt ++ "\n") catch {};
            };
            writer.interface.flush() catch {};
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

const Date = struct {
    year: u64,
    month: u64,
    day: u64,
};

// Algorithm from https://github.com/benjoffe/fast-date-benchmarks/blob/main/algorithms/benjoffe_fast64.hpp
fn daysToDate(days: u64) Date {
    const ERAS = 14704;
    const D_SHIFT = 146097 * ERAS - 719469;
    const Y_SHIFT = 400 * ERAS - 1;
    const SCALE = 32;
    const SHIFT_0 = 30556 * SCALE;
    const SHIFT_1 = 5980 * SCALE;
    const C1 = 505054698555331; // floor(2^64*4/146097)
    const C2 = 50504432782230121; // ceil(2^64*4/1461)
    const C3 = 8619973866219416 * 32 / SCALE; // floor(2^64/2140)

    // 1. Adjust for 100/400 leap year rule.
    const rev = D_SHIFT - days;
    const cen: u64 = @intCast((@as(u128, C1) * rev) >> 64);
    const jul = rev - cen / 4 + cen;

    // 2. Determine year and year-part using an EAF numerator.
    const num = @as(u128, C2) * jul;
    const yrs = Y_SHIFT - @as(u32, @truncate(num >> 64));
    const low: u64 = @truncate(num);

    const ypt: u32 = @truncate((@as(u128, 24451 * SCALE) * low) >> 64);

    const bump = ypt < (3952 * SCALE);
    const shift: u32 = if (bump) SHIFT_1 else SHIFT_0;

    // 3. Year-modulo-bitshift for leap years,
    // also revert to forward direction.
    const N = (yrs % 4) * (16 * SCALE) + shift - ypt;
    const M = N / (2048 * SCALE);
    const D: u64 = @intCast((@as(u128, C3) * (N % (2048 * SCALE))) >> 64);

    const month = M;
    const day = D + 1;
    const year = yrs + @intFromBool(bump);

    return .{ .year = year, .month = month, .day = day };
}

const testing = std.testing;

test "daysToDate" {
    try testing.expectEqualDeep(Date{ .year = 1970, .month = 1, .day = 1 }, daysToDate(0));
    try testing.expectEqualDeep(Date{ .year = 1971, .month = 1, .day = 1 }, daysToDate(365));
    try testing.expectEqualDeep(Date{ .year = 1972, .month = 1, .day = 1 }, daysToDate(730));
    try testing.expectEqualDeep(Date{ .year = 1973, .month = 1, .day = 1 }, daysToDate(1096));
    try testing.expectEqualDeep(Date{ .year = 2023, .month = 1, .day = 1 }, daysToDate(19358));
    try testing.expectEqualDeep(Date{ .year = 2024, .month = 1, .day = 1 }, daysToDate(19723));
}
