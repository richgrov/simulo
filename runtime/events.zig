const Tuple = @import("std").meta.Tuple;

pub const UpdateEvent = struct {
    delta: f32,

    pub const name = "update";

    pub fn toScriptingArgs(self: UpdateEvent) Tuple(&.{f64}) {
        return .{@floatCast(self.delta)};
    }
};

pub const PoseEvent = struct {
    id: u64,
    x: f32,
    y: f32,

    pub const name = "pose";

    pub fn toScriptingArgs(self: PoseEvent) Tuple(&.{ i64, f64, f64 }) {
        return .{ @intCast(self.id), @floatCast(self.x), @floatCast(self.y) };
    }
};
