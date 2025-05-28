const godot = @import("godot.zig");
const gd = godot.gd;

const gd_perception_callbacks = gd.GDExtensionInstanceBindingCallbacks{
    .create_callback = null,
    .free_callback = null,
    .reference_callback = null,
};

const Perception2D = struct {
    object: gd.GDExtensionObjectPtr,

    pub fn detect() void {}
};

fn createPerception2d(data: ?*anyopaque) callconv(.C) gd.GDExtensionObjectPtr {
    _ = data;

    var parent_class_name = godot.createStringName("Node2D");
    defer godot.string_name_destructor.?(&parent_class_name);
    const object: gd.GDExtensionObjectPtr = godot.classdb_construct_object.?(&parent_class_name);

    var gd_perception: *Perception2D = @alignCast(@ptrCast(godot.mem_alloc.?(@sizeOf(Perception2D)).?));
    gd_perception.object = object;

    var class_name = godot.createStringName("Perception2D");
    defer godot.string_name_destructor.?(&class_name);

    godot.object_set_instance.?(object, &class_name, gd_perception);
    godot.object_set_instance_binding.?(object, godot.class_lib, gd_perception, &gd_perception_callbacks);

    return object;
}

fn freePerception2d(data: ?*anyopaque, instance: gd.GDExtensionClassInstancePtr) callconv(.C) void {
    _ = data;

    if (instance == null) {
        return;
    }
    const gd_perception: *Perception2D = @alignCast(@ptrCast(instance));
    godot.mem_free.?(gd_perception);
}

fn initModule(data: ?*anyopaque, level: gd.GDExtensionInitializationLevel) callconv(.C) void {
    if (level != gd.GDEXTENSION_INITIALIZATION_SCENE) {
        return;
    }
    _ = data;

    godot.registerClass(Perception2D, "Node2D", createPerception2d, freePerception2d);
}

fn deinitModule(data: ?*anyopaque, level: gd.GDExtensionInitializationLevel) callconv(.C) void {
    _ = data;
    _ = level;
}

export fn perception_extension_init(
    get_proc_address: gd.GDExtensionInterfaceGetProcAddress,
    lib: gd.GDExtensionClassLibraryPtr,
    init: *gd.GDExtensionInitialization,
) callconv(.C) void {
    godot.initFunctions(get_proc_address, lib);

    init.initialize = initModule;
    init.deinitialize = deinitModule;
    init.minimum_initialization_level = gd.GDEXTENSION_INITIALIZATION_SCENE;
}
