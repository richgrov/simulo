const godot = @import("godot.zig");
const gd = godot.gd;

const gd_perception_callbacks = gd.GDExtensionInstanceBindingCallbacks{
    .create_callback = null,
    .free_callback = null,
    .reference_callback = null,
};

const GdPerception = struct {
    object: gd.GDExtensionObjectPtr,

    pub fn detect() void {}
};

fn createPerception2d(data: ?*anyopaque) callconv(.C) gd.GDExtensionObjectPtr {
    _ = data;

    var parent_class_name = godot.createStringName("Node2D");
    defer godot.string_name_destructor.?(&parent_class_name);
    const object: gd.GDExtensionObjectPtr = godot.classdb_construct_object.?(&parent_class_name);

    var gd_perception: *GdPerception = @alignCast(@ptrCast(godot.mem_alloc.?(@sizeOf(GdPerception)).?));
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
    const gd_perception: *GdPerception = @alignCast(@ptrCast(instance));
    godot.mem_free.?(gd_perception);
}

fn initModule(data: ?*anyopaque, level: gd.GDExtensionInitializationLevel) callconv(.C) void {
    if (level != gd.GDEXTENSION_INITIALIZATION_SCENE) {
        return;
    }
    _ = data;

    var class_name = godot.createStringName("Perception2D");
    defer godot.string_name_destructor.?(&class_name);
    var parent_class_name = godot.createStringName("Node2D");
    defer godot.string_name_destructor.?(&parent_class_name);

    const class_info = gd.GDExtensionClassCreationInfo2{
        .is_virtual = 0,
        .is_abstract = 0,
        .is_exposed = 1,
        .set_func = null,
        .get_func = null,
        .get_property_list_func = null,
        .free_property_list_func = null,
        .property_can_revert_func = null,
        .property_get_revert_func = null,
        .validate_property_func = null,
        .notification_func = null,
        .to_string_func = null,
        .reference_func = null,
        .unreference_func = null,
        .create_instance_func = createPerception2d,
        .free_instance_func = freePerception2d,
        .recreate_instance_func = null,
        .get_virtual_func = null,
        .get_virtual_call_data_func = null,
        .call_virtual_with_data_func = null,
        .get_rid_func = null,
        .class_userdata = null,
    };
    godot.classdb_register_extension_class2.?(godot.class_lib, &class_name, &parent_class_name, &class_info);
    godot.registerMethod("Perception2D", "detect", GdPerception.detect);
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
