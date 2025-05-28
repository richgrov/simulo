const godot = @import("godot.zig");
const gd = godot.gd;

const Perception2D = struct {
    object: gd.GDExtensionObjectPtr,

    pub fn detect() void {}
};

fn initModule(data: ?*anyopaque, level: gd.GDExtensionInitializationLevel) callconv(.C) void {
    if (level != gd.GDEXTENSION_INITIALIZATION_SCENE) {
        return;
    }
    _ = data;

    godot.registerClass(Perception2D, "Node2D");
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
