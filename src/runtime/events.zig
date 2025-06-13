const Tuple = @import("std").meta.Tuple;

pub const UpdateEvent = struct {
    delta: f32,

    pub fn toScriptingArgs(self: UpdateEvent) Tuple(&.{f64}) {
        return .{@floatCast(self.delta)};
    }
};
