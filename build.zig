const std = @import("std");
const builtin = @import("builtin");

const ArrayList = std.ArrayList;
const mem = std.mem;
const fs = std.fs;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const custom_calibration = b.option(bool, "custom_calibration", "Use custom calibration algorithm instead of OpenCV's") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "custom_calibration", custom_calibration);

    const os = target.result.os.tag;
    const engine = createEngine(b, optimize, target, custom_calibration);
    engine.addOptions("build_options", options);

    const check_step = b.step("check", "Check step for ZLS");

    const godot_lib = b.addSharedLibrary(.{
        .name = "gdperception",
        .root_source_file = b.path("src/godot/extension.zig"),
        .target = target,
        .optimize = optimize,
    });
    godot_lib.root_module.addImport("engine", engine);
    godot_lib.addIncludePath(b.path("src"));
    godot_lib.linkLibCpp();
    godot_lib.linkSystemLibrary("onnxruntime");

    if (!custom_calibration) {
        godot_lib.linkSystemLibrary2("opencv4", .{ .preferred_link_mode = .dynamic });
    }

    bundleFramework(b, godot_lib, "gdperception");
    check_step.dependOn(&godot_lib.step);

    const editor = b.addExecutable(.{
        .name = "simulo",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });
    setupExecutable(b, editor);
    editor.root_module.addImport("engine", engine);
    check_step.dependOn(&editor.step);

    bundleExe(b, editor, "simulo");
    if (usesVulkan(os)) {
        editor.step.dependOn(embedVkShader(b, "src/shader/text.vert"));
        editor.step.dependOn(embedVkShader(b, "src/shader/text.frag"));
        editor.step.dependOn(embedVkShader(b, "src/shader/model.vert"));
        editor.step.dependOn(embedVkShader(b, "src/shader/model.frag"));
    }

    const runtime = b.addExecutable(.{
        .name = "runtime",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/runtime/main.zig"),
    });
    runtime.addIncludePath(b.path("src"));
    runtime.linkLibCpp();
    runtime.root_module.addImport("engine", engine);
    runtime.linkSystemLibrary("onnxruntime");
    runtime.linkSystemLibrary("iwasm");

    if (!custom_calibration) {
        runtime.linkSystemLibrary2("opencv4", .{ .preferred_link_mode = .dynamic });
    }

    runtime.root_module.addRPathSpecial("@executable_path/../Frameworks");
    bundleExe(b, runtime, "runtime");
    check_step.dependOn(&runtime.step);
}

fn embedVkShader(b: *std.Build, comptime file: []const u8) *std.Build.Step {
    const out_file = file ++ ".spv";
    const run = b.addSystemCommand(&[_][]const u8{ "glslc", file, "-o", out_file });
    return &run.step;
}

fn bundleExe(b: *std.Build, exe: *std.Build.Step.Compile, comptime name: []const u8) void {
    const install_exe = b.addInstallArtifact(exe, .{
        .dest_dir = .{
            .override = .{
                .custom = name ++ ".app/Contents/MacOS",
            },
        },
    });

    const install_plist = b.addInstallFile(b.path("src/res/Info.plist"), name ++ ".app/Contents/Info.plist");

    const gen_air = b.addSystemCommand(&[_][]const u8{ "xcrun", "-sdk", "macosx", "metal", "-c", "src/shader/text.metal", "-o", "text.air" });
    const gen_metallib = b.addSystemCommand(&[_][]const u8{ "xcrun", "-sdk", "macosx", "metallib", "text.air", "-o", "default.metallib" });
    gen_metallib.step.dependOn(&gen_air.step);
    const install_metallib = b.addInstallFile(b.path("default.metallib"), name ++ ".app/Contents/Resources/default.metallib");
    install_metallib.step.dependOn(&gen_metallib.step);

    b.getInstallStep().dependOn(&install_exe.step);
    b.getInstallStep().dependOn(&install_plist.step);
    b.getInstallStep().dependOn(&install_metallib.step);
}

fn bundleFramework(b: *std.Build, lib: *std.Build.Step.Compile, comptime name: []const u8) void {
    const install_framework = b.addInstallArtifact(lib, .{
        .dest_dir = .{
            .override = .{
                .custom = name ++ ".framework/Versions/A",
            },
        },
    });

    b.getInstallStep().dependOn(&install_framework.step);
}

fn createEngine(b: *std.Build, optimize: std.builtin.OptimizeMode, target: std.Build.ResolvedTarget, custom_calibration: bool) *std.Build.Module {
    const engine = b.addModule("engine", .{
        .root_source_file = b.path("src/engine.zig"),
        .target = target,
    });
    engine.addIncludePath(b.path("src/"));

    if (optimize == .Debug) {
        engine.addCMacro("SIMULO_DEBUG", "");
        engine.addCMacro("VKAD_DEBUG", "");
    }

    var cpp_sources = ArrayList([]const u8).init(b.allocator);
    defer cpp_sources.deinit();

    cpp_sources.appendSlice(&[_][]const u8{
        "src/entity/player.cc",
        "src/geometry/circle.cc",
        "src/geometry/model.cc",
        "src/geometry/shape.cc",
        "src/image/png.cc",
        "src/ttf/ttf.cc",
        "src/ui/font.cc",
        "src/ui/ui.cc",
        "src/util/rational.cc",
        "src/app.cc",
        "src/stl.cc",
    }) catch unreachable;

    if (!custom_calibration) {
        cpp_sources.append("src/inference/calibrate.cc") catch unreachable;
    }

    const os = target.result.os.tag;
    if (os == .windows) {
        cpp_sources.append("src/window/win32/window.cc") catch unreachable;
        engine.linkSystemLibrary("vulkan-1", .{});
    } else if (os == .macos) {
        cpp_sources.appendSlice(&[_][]const u8{
            "src/gpu/metal/buffer.mm",
            "src/gpu/metal/command_queue.mm",
            "src/gpu/metal/gpu.mm",
            "src/gpu/metal/image.mm",
            "src/gpu/metal/render_pipeline.mm",
            "src/render/mt_renderer.mm",
            "src/window/macos/window.mm",
            "src/camera/macos_camera.mm",
        }) catch unreachable;

        engine.linkFramework("Foundation", .{});
        engine.linkFramework("AppKit", .{});
        engine.linkFramework("Metal", .{});
        engine.linkFramework("QuartzCore", .{});
        engine.linkFramework("AVFoundation", .{});
        engine.linkFramework("CoreImage", .{});
        engine.linkFramework("CoreMedia", .{});
        engine.linkFramework("CoreVideo", .{});
    } else if (os == .linux) {
        cpp_sources.appendSlice(&[_][]const u8{
            "src/window/linux/wl_deleter.cc",
            "src/window/linux/wl_window.cc",
            "src/window/linux/x11_window.cc",
        }) catch unreachable;

        engine.addCSourceFiles(.{
            .files = &[_][]const u8{
                "src/window/linux/pointer-constraints-unstable-v1-protocol.c",
                "src/window/linux/relative-pointer-unstable-v1-protocol.c",
                "src/window/linux/xdg-shell-protocol.c",
            },
        });

        engine.linkSystemLibrary("vulkan", .{});
        engine.linkSystemLibrary("X11", .{});
        engine.linkSystemLibrary("Xi", .{});
        engine.linkSystemLibrary("wayland-client", .{});
        engine.linkSystemLibrary("wayland-protocols", .{});
        engine.linkSystemLibrary("xkbcommon", .{});
    }

    if (usesVulkan(os)) {
        cpp_sources.appendSlice(&[_][]const u8{
            "src/render/vk_renderer.cc",
            "src/gpu/vulkan/command_pool.cc",
            "src/gpu/vulkan/descriptor_pool.cc",
            "src/gpu/vulkan/device.cc",
            "src/gpu/vulkan/gpu.cc",
            "src/gpu/vulkan/image.cc",
            "src/gpu/vulkan/pipeline.cc",
            "src/gpu/vulkan/physical_device.cc",
            "src/gpu/vulkan/shader.cc",
            "src/gpu/vulkan/swapchain.cc",
            "src/gpu/vulkan/buffer.cc",
        }) catch unreachable;
    }

    engine.addCSourceFiles(.{
        .files = cpp_sources.items,
        .flags = &[_][]const u8{
            "-std=c++20",
        },
    });

    engine.addCSourceFile(.{
        .file = b.path("src/vendor/pocketpy/pocketpy.c"),
    });

    if (!custom_calibration) {
        engine.linkSystemLibrary("opencv4", .{ .preferred_link_mode = .dynamic });
    }

    engine.linkSystemLibrary("onnxruntime", .{});
    engine.linkSystemLibrary("libdeflate", .{});

    return engine;
}

fn setupExecutable(b: *std.Build, mod: *std.Build.Step.Compile) void {
    mod.linkLibCpp();
    mod.addIncludePath(b.path("src"));
}

fn usesVulkan(os: std.Target.Os.Tag) bool {
    return os == .windows or os == .linux;
}
