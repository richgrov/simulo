const std = @import("std");

const engine = @import("engine");

const godot = @import("godot.zig");
const gd = godot.gd;

const ffi = @cImport({
    @cInclude("ffi.h");
});

var initialized = false;
var pose_detection: engine.PoseDetector = undefined;

const Perception2D = struct {
    object: gd.GDExtensionObjectPtr,

    pub fn num_detections(_: *Perception2D) i64 {
        return 0;
    }

    pub fn get_detection_score(_: *Perception2D, _: i64, _: i64) f64 {
        return 0.0;
    }

    pub fn get_detection_keypoint(_: *Perception2D, _: i64, _: i64) @Vector(2, f32) {
        return @Vector(2, f32){ 0.0, 0.0 };
    }

    pub fn start(_: *Perception2D) void {
        if (!initialized) {
            initialized = true;
            pose_detection = engine.PoseDetector.init();
            pose_detection.start() catch unreachable;
        }
    }

    pub fn stop(_: *Perception2D) void {
        pose_detection.stop();
    }

    pub fn is_calibrated(_: *Perception2D) bool {
        return false;
    }
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
