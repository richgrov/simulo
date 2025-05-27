const engine = @import("engine");

const gd = @cImport({
    @cInclude("godot/godot-cpp/gdextension/gdextension_interface.h");
});

comptime {
    _ = engine;
}

var variant_get_ptr_destructor: gd.GDExtensionInterfaceVariantGetPtrDestructor = undefined;
var classdb_construct_object: gd.GDExtensionInterfaceClassdbConstructObject = undefined;
var classdb_register_extension_class2: gd.GDExtensionInterfaceClassdbRegisterExtensionClass2 = undefined;
var string_name_new_with_latin1_chars: gd.GDExtensionInterfaceStringNameNewWithLatin1Chars = undefined;
var object_set_instance: gd.GDExtensionInterfaceObjectSetInstance = undefined;
var object_set_instance_binding: gd.GDExtensionInterfaceObjectSetInstanceBinding = undefined;
var mem_alloc: gd.GDExtensionInterfaceMemAlloc = undefined;
var mem_free: gd.GDExtensionInterfaceMemFree = undefined;
var string_name_destructor: gd.GDExtensionPtrDestructor = undefined;

const GdPerception = struct {
    object: gd.GDExtensionObjectPtr,
};

const gd_perception_callbacks = gd.GDExtensionInstanceBindingCallbacks{
    .create_callback = null,
    .free_callback = null,
    .reference_callback = null,
};

var gd_class_library: ?*anyopaque = undefined;

fn createPerception2d(data: ?*anyopaque) callconv(.C) gd.GDExtensionObjectPtr {
    _ = data;

    var parent_class_name: StringName = undefined;
    string_name_new_with_latin1_chars.?(&parent_class_name, "Node2D", 0);
    defer string_name_destructor.?(&parent_class_name);
    const object: gd.GDExtensionObjectPtr = classdb_construct_object.?(&parent_class_name);

    var gd_perception: *GdPerception = @alignCast(@ptrCast(mem_alloc.?(@sizeOf(GdPerception)).?));
    gd_perception.object = object;

    var class_name: StringName = undefined;
    string_name_new_with_latin1_chars.?(&class_name, "Perception2D", 0);
    defer string_name_destructor.?(&class_name);

    object_set_instance.?(object, &class_name, gd_perception);
    object_set_instance_binding.?(object, gd_class_library, gd_perception, &gd_perception_callbacks);

    return object;
}

fn freePerception2d(data: ?*anyopaque, instance: gd.GDExtensionClassInstancePtr) callconv(.C) void {
    _ = data;

    if (instance == null) {
        return;
    }
    const gd_perception: *GdPerception = @alignCast(@ptrCast(instance));
    mem_free.?(gd_perception);
}

fn initModule(data: ?*anyopaque, level: gd.GDExtensionInitializationLevel) callconv(.C) void {
    _ = data;
    _ = level;
}

fn deinitModule(data: ?*anyopaque, level: gd.GDExtensionInitializationLevel) callconv(.C) void {
    _ = data;
    _ = level;
}

const StringName = usize;

export fn perception_extension_init(
    get_proc_address: gd.GDExtensionInterfaceGetProcAddress,
    lib: gd.GDExtensionClassLibraryPtr,
    init: *gd.GDExtensionInitialization,
) callconv(.C) void {
    const getProcAddress = get_proc_address.?;
    variant_get_ptr_destructor = @ptrCast(getProcAddress("variant_get_ptr_destructor"));
    classdb_construct_object = @ptrCast(getProcAddress("classdb_construct_object"));
    classdb_register_extension_class2 = @ptrCast(getProcAddress("classdb_register_extension_class2"));
    string_name_new_with_latin1_chars = @ptrCast(getProcAddress("string_name_new_with_latin1_chars"));
    object_set_instance = @ptrCast(getProcAddress("object_set_instance"));
    object_set_instance_binding = @ptrCast(getProcAddress("object_set_instance_binding"));
    mem_alloc = @ptrCast(getProcAddress("mem_alloc"));
    mem_free = @ptrCast(getProcAddress("mem_free"));
    string_name_destructor = variant_get_ptr_destructor.?(gd.GDEXTENSION_VARIANT_TYPE_STRING_NAME);

    gd_class_library = lib;

    var class_name: StringName = undefined;
    string_name_new_with_latin1_chars.?(&class_name, "Perception2D", 0);
    defer string_name_destructor.?(&class_name);
    var parent_class_name: StringName = undefined;
    string_name_new_with_latin1_chars.?(&parent_class_name, "Node2D", 0);
    defer string_name_destructor.?(&parent_class_name);

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
    classdb_register_extension_class2.?(lib, &class_name, &parent_class_name, &class_info);

    init.initialize = initModule;
    init.deinitialize = deinitModule;
    init.minimum_initialization_level = gd.GDEXTENSION_INITIALIZATION_SCENE;
}
