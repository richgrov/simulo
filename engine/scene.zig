const std = @import("std");
const builtin = @import("builtin");

const util = @import("util");
const CheckedSlab = util.CheckedSlab;

pub const Object = struct {
    id: u32,
    deleted: bool,

    children: ?util.IntSet(u32, 64),
    parent: ?u32,
    this: i32,

    pub fn init() Object {
        return .{
            .id = undefined,
            .deleted = false,
            .children = null,
            .parent = null,
            .this = undefined,
        };
    }

    pub fn deinit(self: *Object, allocator: std.mem.Allocator) void {
        if (self.deleted) {
            return;
        }

        if (self.children) |*children| {
            children.deinit(allocator);
        }

        self.deleted = true;
    }
};

pub const Scene = struct {
    allocator: std.mem.Allocator,
    objects: CheckedSlab(Object),
    root_object: ?u32,

    pub fn init(allocator: std.mem.Allocator) error{OutOfMemory}!Scene {
        var objects = try CheckedSlab(Object).init(allocator, 128);
        errdefer objects.deinit();

        return .{
            .allocator = allocator,
            .objects = objects,
            .root_object = null,
        };
    }

    pub fn deinit(self: *Scene) void {
        const Deleter = struct {
            fn deinit(self_: *Scene, id: u32, obj: *Object) void {
                obj.deinit(self_.allocator);
                self_.objects.delete(id) catch unreachable;
            }
        };

        if (self.root_object) |id| {
            self.dfs(id, *Scene, self, Deleter.deinit) catch unreachable;
            self.root_object = null;
        }

        for (0..self.objects.num_cells()) |id| {
            if (self.objects.get(id)) |obj| {
                Deleter.deinit(self, @intCast(id), obj);
            }
        }

        self.objects.deinit();
    }

    pub fn createObject(self: *Scene) error{OutOfMemory}!u32 {
        const obj = Object.init();
        const object_id, const obj_ptr = try self.objects.insert(obj);
        obj_ptr.*.id = @intCast(object_id);
        return @intCast(object_id);
    }

    pub fn addChild(self: *Scene, parent: u32, child: u32) error{ OutOfMemory, ObjectNotFound, ObjectAlreadyHasParent }!void {
        const parent_obj = self.objects.get(parent) orelse return error.ObjectNotFound;

        const child_obj = self.objects.get(child) orelse return error.ObjectNotFound;
        if (child_obj.parent) |_| {
            return error.ObjectAlreadyHasParent;
        }

        child_obj.parent = parent;

        if (parent_obj.children) |*children| {
            try children.put(self.allocator, child);
        } else {
            var children = try util.IntSet(u32, 64).init(self.allocator, 1);
            errdefer children.deinit(self.allocator);

            try children.put(self.allocator, child);
            parent_obj.children = children;
        }
    }

    pub fn setRoot(self: *Scene, id: u32) error{ RootAlreadySet, ObjectAlreadyHasParent }!void {
        if (self.root_object) |_| {
            return error.RootAlreadySet;
        }

        self.root_object = id;
    }

    pub fn get(self: *Scene, id: u32) ?*Object {
        return self.objects.get(id);
    }

    pub fn delete(self: *Scene, id: u32) error{ ObjectNotFound, ObjectHasChildren }!void {
        const obj = self.objects.get(id) orelse return error.ObjectNotFound;
        if (obj.children) |*children| {
            if (!children.empty()) {
                return error.ObjectHasChildren;
            }
        }

        self.objects.delete(id) catch return error.ObjectNotFound;
    }

    pub fn dfs(
        self: *Scene,
        id: u32,
        UserData: type,
        user_data: UserData,
        comptime visitor: fn (user_data: UserData, id: u32, obj: *Object) void,
    ) error{ObjectNotFound}!void {
        const obj = self.objects.get(id) orelse return error.ObjectNotFound;
        self.doDfs(id, obj, UserData, user_data, visitor);
    }

    fn doDfs(
        self: *Scene,
        id: u32,
        obj: *Object,
        UserData: type,
        user_data: UserData,
        comptime visitor: fn (user_data: UserData, id: u32, obj: *Object) void,
    ) void {
        if (obj.children) |*children| {
            for (0..children.bucketCount()) |bucket| {
                for (children.bucketItems(bucket)) |child_id| {
                    self.doDfs(child_id, self.objects.get(child_id).?, UserData, user_data, visitor);
                }
            }
        }

        visitor(user_data, id, obj);
    }
};
