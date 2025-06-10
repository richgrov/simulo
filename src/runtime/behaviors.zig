const std = @import("std");

const engine = @import("engine");
const Mat4 = engine.math.Mat4;

const runtime_module = @import("runtime.zig");
const Runtime = runtime_module.Runtime;
const GameObject = runtime_module.GameObject;

const events = @import("events.zig");

pub const MovementBehavior = extern struct {
    behavior: Behavior,
    object: *GameObject,
    dx: f32,
    dy: f32,

    const movement_behavior_events = [_]*const fn (runtime: *Runtime, self: *anyopaque, event: *anyopaque) callconv(.C) void{
        MovementBehavior.update_handler,
    };

    pub fn init(self: *MovementBehavior, object: *GameObject, dx: f32, dy: f32) void {
        self.behavior = .{
            .behavior_instance = @ptrCast(self),
            .num_event_handlers = 1,
            .event_handlers = @ptrCast(&movement_behavior_events),
        };

        self.object = object;
        self.dx = dx;
        self.dy = dy;
    }

    pub fn py__init__(user_data: *anyopaque, self_any: engine.Scripting.Any, object_any: engine.Scripting.Any, dx: f64, dy: f64) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_data));
        const self = runtime.scripting.getSelf(MovementBehavior, self_any) orelse return;
        const object = runtime.scripting.getSelf(GameObject, object_any) orelse return;
        runtime.scripting.keepMemberAlive(self_any, object_any, "object");
        self.init(object, @floatCast(dx), @floatCast(dy));
    }

    fn update(runtime: *Runtime, self: *MovementBehavior, delta_ms: f32) void {
        self.object.x += self.dx * delta_ms;
        self.object.y += self.dy * delta_ms;
        const translate = Mat4.translate(.{ self.object.x, self.object.y, 0 });
        const scale = Mat4.scale(.{ 5, 5, 1 });
        const transform = translate.matmul(&scale);
        runtime.renderer.setObjectTransform(self.object.handle, transform);
    }

    pub fn update_handler(runtime: *Runtime, self_any: *anyopaque, event_any: *const anyopaque) callconv(.C) void {
        const self: *MovementBehavior = @alignCast(@ptrCast(self_any));
        const event: *const events.UpdateEvent = @alignCast(@ptrCast(event_any));
        MovementBehavior.update(runtime, self, event.delta);
    }
};

pub const Behavior = extern struct {
    behavior_instance: *anyopaque,
    num_event_handlers: usize,
    event_handlers: [*]const *const fn (runtime: *Runtime, self: *anyopaque, event: *const anyopaque) callconv(.C) void,
};

pub const LifetimeBehavior = struct {
    behavior: Behavior,
    object: *GameObject,
    lifetime: f32,
    timer: f32,

    const lifetime_behavior_events = [_]*const fn (runtime: *Runtime, self: *anyopaque, event: *anyopaque) callconv(.C) void{
        LifetimeBehavior.update_handler,
    };

    pub fn init(self: *LifetimeBehavior, object: *GameObject, lifetime: f32) void {
        self.behavior = .{
            .behavior_instance = @ptrCast(self),
            .num_event_handlers = 1,
            .event_handlers = @ptrCast(&lifetime_behavior_events),
        };

        self.object = object;
        self.lifetime = lifetime;
        self.timer = 0;
    }

    pub fn py__init__(user_data: *anyopaque, self_any: engine.Scripting.Any, object_any: engine.Scripting.Any, lifetime: f64) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_data));
        const self = runtime.scripting.getSelf(LifetimeBehavior, self_any) orelse return;
        const object = runtime.scripting.getSelf(GameObject, object_any) orelse return;
        runtime.scripting.keepMemberAlive(self_any, object_any, "object");
        self.init(object, @floatCast(lifetime));
    }

    fn update(runtime: *Runtime, self: *LifetimeBehavior, delta_ms: f32) void {
        self.timer += delta_ms;
        if (self.timer >= self.lifetime) {
            self.object.delete(runtime);
        }
    }

    pub fn update_handler(runtime: *Runtime, self_any: *anyopaque, event_any: *const anyopaque) callconv(.C) void {
        const self: *LifetimeBehavior = @alignCast(@ptrCast(self_any));
        const event: *const events.UpdateEvent = @alignCast(@ptrCast(event_any));
        LifetimeBehavior.update(runtime, self, event.delta);
    }
};
