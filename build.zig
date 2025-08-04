const std = @import("std");
const builtin = @import("builtin");

const ArrayList = std.ArrayList;
const mem = std.mem;
const fs = std.fs;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const custom_api_host = b.option([]const u8, "api_host", "Override API host") orelse "api.simulo.tech";
    const custom_api_port = b.option(u16, "api_port", "Override API port") orelse 443;
    const api_tls = b.option(bool, "api_tls", "Use TLS for API connection") orelse true;
    const wasm_path = b.option([]const u8, "wasm_path", "Override path to read WASM binary from");
    const new_wasm = b.option(bool, "new_wasm", "Use the experimental WASM JIT compiler") orelse false;

    const options = b.addOptions();
    options.addOption([]const u8, "api_host", custom_api_host);
    options.addOption(u16, "api_port", custom_api_port);
    options.addOption(bool, "api_tls", api_tls);
    options.addOption(?[]const u8, "wasm_path", wasm_path);
    options.addOption(bool, "new_wasm", new_wasm);

    const util = b.createModule(.{
        .root_source_file = b.path("util/util.zig"),
    });

    const util_tests = b.addTest(.{
        .root_source_file = b.path("util/util.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(util_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    const engine = createEngine(b, target);
    engine.addImport("util", util);

    const check_step = b.step("check", "Check step for ZLS");

    // Legacy Godot & Editor not maintained for now
    //const godot_lib = b.addSharedLibrary(.{
    //    .name = "gdperception",
    //    .root_source_file = b.path("godot/extension.zig"),
    //    .target = target,
    //    .optimize = optimize,
    //});
    //godot_lib.root_module.addImport("util", util);
    //godot_lib.root_module.addImport("engine", engine);
    //godot_lib.addIncludePath(b.path("godot"));
    //godot_lib.linkLibCpp();
    //godot_lib.linkSystemLibrary("onnxruntime");

    //godot_lib.linkSystemLibrary2("opencv4", .{ .preferred_link_mode = .dynamic });

    //bundleFramework(b, godot_lib, "gdperception");
    //check_step.dependOn(&godot_lib.step);

    //const editor = b.addExecutable(.{
    //    .name = "simulo",
    //    .target = target,
    //    .optimize = optimize,
    //    .root_source_file = b.path("legacy-editor/main.zig"),
    //});
    //setupExecutable(b, editor);
    //editor.root_module.addImport("engine", engine);

    //editor.addCSourceFiles(.{
    //    .files = &[_][]const u8{
    //        "legacy-editor/entity/player.cc",
    //        "legacy-editor/geometry/circle.cc",
    //        "legacy-editor/geometry/model.cc",
    //        "legacy-editor/geometry/shape.cc",
    //        "legacy-editor/image/png.cc",
    //        "legacy-editor/ttf/ttf.cc",
    //        "legacy-editor/ui/font.cc",
    //        "legacy-editor/ui/ui.cc",
    //        "legacy-editor/util/rational.cc",
    //        "legacy-editor/app.cc",
    //        "legacy-editor/stl.cc",
    //    },
    //    .flags = &[_][]const u8{
    //        "-std=c++20",
    //    },
    //});
    //editor.addIncludePath(b.path("legacy-editor"));

    //check_step.dependOn(&editor.step);

    //bundleExe(b, editor, "simulo");
    //if (usesVulkan(os)) {
    //    editor.step.dependOn(embedVkShader(b, "src/shader/text.vert"));
    //    editor.step.dependOn(embedVkShader(b, "src/shader/text.frag"));
    //    editor.step.dependOn(embedVkShader(b, "src/shader/model.vert"));
    //    editor.step.dependOn(embedVkShader(b, "src/shader/model.frag"));
    //}

    const websocket = b.dependency("websocket", .{
        .target = target,
        .optimize = optimize,
    });

    const runtime = createRuntime(b, optimize, target);
    runtime.root_module.addOptions("build_options", options);
    runtime.root_module.addImport("engine", engine);
    runtime.root_module.addImport("util", util);
    runtime.root_module.addImport("websocket", websocket.module("websocket"));
    runtime.root_module.addRPathSpecial("@executable_path/../Frameworks");
    try bundleExe(b, runtime, target.result.os.tag, &[_][]const u8{
        "runtime/inference/rtmo-m.onnx",
    });
    check_step.dependOn(&runtime.step);
}

fn embedVkShader(b: *std.Build, comptime file: []const u8) *std.Build.Step {
    const out_file = file ++ ".spv";
    const run = b.addSystemCommand(&[_][]const u8{ "glslc", file, "-o", out_file });
    return &run.step;
}

fn bundleExe(b: *std.Build, exe: *std.Build.Step.Compile, target: std.Target.Os.Tag, resources: []const []const u8) !void {
    const install_step = b.getInstallStep();
    if (target == .macos) {
        const install_exe = b.addInstallArtifact(exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = try std.fmt.allocPrint(b.allocator, "{s}.app/Contents/MacOS", .{exe.name}),
                },
            },
        });

        const install_plist = b.addInstallFile(
            b.path("runtime/res/Info.plist"),
            try std.fmt.allocPrint(b.allocator, "{s}.app/Contents/Info.plist", .{exe.name}),
        );

        const gen_air = b.addSystemCommand(&[_][]const u8{ "xcrun", "-sdk", "macosx", "metal", "-c", "runtime/shader/text.metal", "-o", "text.air" });
        const gen_metallib = b.addSystemCommand(&[_][]const u8{ "xcrun", "-sdk", "macosx", "metallib", "text.air", "-o", "default.metallib" });
        gen_metallib.step.dependOn(&gen_air.step);
        const install_metallib = b.addInstallFile(b.path("default.metallib"), try std.fmt.allocPrint(b.allocator, "{s}.app/Contents/Resources/default.metallib", .{exe.name}));
        install_metallib.step.dependOn(&gen_metallib.step);

        install_step.dependOn(&install_exe.step);
        install_step.dependOn(&install_plist.step);
        install_step.dependOn(&install_metallib.step);
    } else {
        install_step.dependOn(&b.addInstallArtifact(exe, .{}).step);
        install_step.dependOn(embedVkShader(b, "runtime/shader/text.vert"));
        install_step.dependOn(embedVkShader(b, "runtime/shader/text.frag"));
        install_step.dependOn(embedVkShader(b, "runtime/shader/model.vert"));
        install_step.dependOn(embedVkShader(b, "runtime/shader/model.frag"));
    }

    for (resources) |resource| {
        const file_name = resource[std.mem.lastIndexOf(u8, resource, "/").? + 1 ..];

        const destination = if (target == .macos)
            try std.fmt.allocPrint(b.allocator, "{s}.app/Contents/Resources/{s}", .{ exe.name, file_name })
        else
            file_name;

        const install_resource = b.addInstallFile(b.path(resource), destination);
        install_step.dependOn(&install_resource.step);
    }
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

fn createEngine(b: *std.Build, target: std.Build.ResolvedTarget) *std.Build.Module {
    const engine = b.addModule("engine", .{
        .root_source_file = b.path("engine/engine.zig"),
        .target = target,
    });

    engine.linkSystemLibrary("onnxruntime", .{});
    engine.linkSystemLibrary("libdeflate", .{});

    return engine;
}

fn createRuntime(b: *std.Build, optimize: std.builtin.OptimizeMode, target: std.Build.ResolvedTarget) *std.Build.Step.Compile {
    const runtime = b.addExecutable(.{
        .name = "runtime",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("runtime/main.zig"),
    });
    runtime.addIncludePath(b.path("runtime"));
    runtime.linkLibCpp();
    runtime.linkSystemLibrary("onnxruntime");
    runtime.linkSystemLibrary("iwasm");

    var cpp_sources = ArrayList([]const u8).init(b.allocator);
    defer cpp_sources.deinit();
    cpp_sources.appendSlice(&[_][]const u8{
        "runtime/app.cc",
        "runtime/inference/calibrate.cc",
        "runtime/image/stb_image.cc",
    }) catch unreachable;

    const os = target.result.os.tag;
    if (os == .windows) {
        cpp_sources.append("src/window/win32/window.cc") catch unreachable;
        runtime.linkSystemLibrary("vulkan-1");
    } else if (os == .macos) {
        cpp_sources.appendSlice(&[_][]const u8{
            "runtime/gpu/metal/command_queue.mm",
            "runtime/gpu/metal/gpu.mm",
            "runtime/gpu/metal/image.mm",
            "runtime/gpu/metal/render_pipeline.mm",
            "runtime/render/mt_renderer.mm",
            "runtime/window/macos/window.mm",
            "runtime/camera/macos_camera.mm",
        }) catch unreachable;

        runtime.linkFramework("Foundation");
        runtime.linkFramework("AppKit");
        runtime.linkFramework("Metal");
        runtime.linkFramework("QuartzCore");
        runtime.linkFramework("AVFoundation");
        runtime.linkFramework("CoreImage");
        runtime.linkFramework("CoreMedia");
        runtime.linkFramework("CoreVideo");
    } else if (os == .linux) {
        cpp_sources.appendSlice(&[_][]const u8{
            "runtime/window/linux/wl_deleter.cc",
            "runtime/window/linux/wl_window.cc",
            "runtime/window/linux/x11_window.cc",
        }) catch unreachable;

        runtime.addCSourceFiles(.{
            .files = &[_][]const u8{
                "runtime/window/linux/pointer-constraints-unstable-v1-protocol.c",
                "runtime/window/linux/relative-pointer-unstable-v1-protocol.c",
                "runtime/window/linux/fractional-scale-protocol.c",
                "runtime/window/linux/viewporter-protocol.c",
                "runtime/window/linux/xdg-shell-protocol.c",
            },
        });

        runtime.linkSystemLibrary("vulkan");
        runtime.linkSystemLibrary("X11");
        runtime.linkSystemLibrary("Xi");
        runtime.linkSystemLibrary("wayland-client");
        runtime.linkSystemLibrary("wayland-protocols");
        runtime.linkSystemLibrary("xkbcommon");
    }

    if (usesVulkan(os)) {
        cpp_sources.appendSlice(&[_][]const u8{
            "runtime/render/vk_renderer.cc",
            "runtime/gpu/vulkan/command_pool.cc",
            "runtime/gpu/vulkan/descriptor_pool.cc",
            "runtime/gpu/vulkan/device.cc",
            "runtime/gpu/vulkan/gpu.cc",
            "runtime/gpu/vulkan/image.cc",
            "runtime/gpu/vulkan/pipeline.cc",
            "runtime/gpu/vulkan/physical_device.cc",
            "runtime/gpu/vulkan/shader.cc",
            "runtime/gpu/vulkan/swapchain.cc",
            "runtime/gpu/vulkan/buffer.cc",
        }) catch unreachable;

        if (optimize == .Debug) {
            runtime.root_module.addCMacro("VKAD_DEBUG", "true");
        }
    }

    runtime.linkSystemLibrary2("opencv4", .{ .preferred_link_mode = .dynamic });

    runtime.addCSourceFiles(.{
        .files = cpp_sources.items,
        .flags = &[_][]const u8{
            "-std=c++20",
        },
    });

    return runtime;
}

fn setupExecutable(b: *std.Build, mod: *std.Build.Step.Compile) void {
    mod.linkLibCpp();
    mod.addIncludePath(b.path("src"));
}

fn usesVulkan(os: std.Target.Os.Tag) bool {
    return os == .windows or os == .linux;
}
