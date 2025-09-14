const std = @import("std");

const util = @import("util");
const FixedArrayList = util.FixedArrayList;

pub fn Profiler(comptime name: []const u8, comptime Enum: type) type {
    return struct {
        timer: std.time.Timer,
        durations: [@typeInfo(Enum).@"enum".fields.len]u64,

        const Self = @This();

        pub fn init() Self {
            return .{
                .timer = std.time.Timer.start() catch unreachable,
                .durations = [_]u64{0} ** @typeInfo(Enum).@"enum".fields.len,
            };
        }

        pub fn log(self: *Self, comptime label: Enum) void {
            const enum_index = @intFromEnum(label);
            if (enum_index < self.durations.len) {
                self.durations[enum_index] = @min(self.durations[enum_index] + self.timer.lap(), std.math.maxInt(u64));
            } else {
                std.debug.print("unable to log " ++ @tagName(label) ++ " for profiler " ++ name ++ "\n", .{});
            }
        }

        pub fn format(self: *Self, writer: anytype) !void {
            try writer.print("Profiler " ++ name, .{});
            const fields = @typeInfo(Enum).@"enum".fields;
            inline for (fields, 0..) |field, i| {
                try writer.print("\n  " ++ field.name ++ ": {D}", .{self.durations[i]});
            }
        }

        pub fn reset(self: *Self) void {
            @memset(&self.durations, 0);
        }
    };
}
