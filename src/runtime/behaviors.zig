const std = @import("std");

const engine = @import("engine");
const reflect = engine.utils.reflect;
const Mat4 = engine.math.Mat4;

const runtime_module = @import("runtime.zig");
const Runtime = runtime_module.Runtime;
const GameObject = runtime_module.GameObject;

const events = @import("events.zig");

pub const MovementBehavior = extern struct {
    behavior: Behavior,
    object: *GameObject,
    move: @Vector(3, f32) align(8), // TODO: probably causes performance issues, but PocketPy can't allocate align(16)

    const handlers = [_]*const fn (runtime: *Runtime, self: *anyopaque, event: *anyopaque) callconv(.C) void{
        MovementBehavior.update_handler,
    };

    const types = [_]reflect.TypeId{
        reflect.typeId(events.UpdateEvent),
    };

    pub fn init(self: *MovementBehavior, object: *GameObject, dx: f32, dy: f32) void {
        self.behavior = .{
            .behavior_instance = @ptrCast(self),
            .num_event_handlers = 1,
            .event_handlers = @ptrCast(&handlers),
            .event_handler_types = @ptrCast(&types),
        };

        self.object = object;
        self.move = .{ dx, dy, 0 };
    }

    pub fn py__init__(user_data: *anyopaque, self_any: engine.Scripting.Any, object_any: engine.Scripting.Any, dx: f64, dy: f64) void {
        const runtime: *Runtime = @alignCast(@ptrCast(user_data));
        const self = runtime.scripting.getSelf(MovementBehavior, self_any) orelse return;
        const object = runtime.scripting.getSelf(GameObject, object_any) orelse return;
        runtime.scripting.keepMemberAlive(self_any, object_any, "object");
        self.init(object, @floatCast(dx), @floatCast(dy));
    }

    fn update(runtime: *Runtime, self: *MovementBehavior, delta_ms: f32) void {
        const delta_vec: @Vector(3, f32) = @splat(delta_ms);
        self.object.pos += self.move * delta_vec;
        runtime.renderer.setObjectTransform(self.object.handle, self.object.calculateTransform());
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
    event_handler_types: [*]const reflect.TypeId,
};

pub const LifetimeBehavior = extern struct {
    behavior: Behavior,
    object: *GameObject,
    lifetime: f32,
    timer: f32,

    const handlers = [_]*const fn (runtime: *Runtime, self: *anyopaque, event: *anyopaque) callconv(.C) void{
        LifetimeBehavior.update_handler,
    };

    const types = [_]reflect.TypeId{
        reflect.typeId(events.UpdateEvent),
    };

    pub fn init(self: *LifetimeBehavior, object: *GameObject, lifetime: f32) void {
        self.behavior = .{
            .behavior_instance = @ptrCast(self),
            .num_event_handlers = 1,
            .event_handlers = @ptrCast(&handlers),
            .event_handler_types = @ptrCast(&types),
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
