const std = @import("std");

const util = @import("util");
const FixedArrayList = util.FixedArrayList;

pub const Log = struct {
    label: u32,
    us: u32,
};

pub const Logs = FixedArrayList(Log, 32);
pub const Labels = FixedArrayList([]const u8, 32);

pub fn Profiler(comptime name: []const u8, comptime Enum: type) type {
    return struct {
        timer: std.time.Timer,
        logs: Logs,

        const Self = @This();

        pub fn init() Self {
            return .{
                .timer = std.time.Timer.start() catch unreachable,
                .logs = Logs.init(),
            };
        }

        pub fn reset(self: *Self) void {
            self.timer.reset();
        }

        pub fn log(self: *Self, label: Enum) void {
            self.logs.append(.{
                .label = @intCast(@intFromEnum(label)),
                .us = @intCast(@min(self.timer.lap() / 1000, std.math.maxInt(u32))),
            }) catch {
                std.debug.print("unable to log {s} for profiler {s}\n", .{ @tagName(label), name });
            };
        }

        pub fn profilerName() []const u8 {
            return name;
        }

        pub fn labels() Labels {
            const info = switch (@typeInfo(Enum)) {
                .@"enum" => |e| e,
                else => @compileError("profiler labels must be an enum"),
            };

            var names = Labels.init();
            inline for (0..info.fields.len) |i| {
                names.append(info.fields[i].name) catch unreachable;
            }
            return names;
        }

        pub fn end(self: *Self) Logs {
            const result = self.logs;
            self.logs = Logs.init();
            return result;
        }
    };
}
