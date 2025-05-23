const std = @import("std");
const builtin = @import("builtin");
const ArrayList = std.ArrayList;
const mem = std.mem;
const fs = std.fs;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const os = target.result.os.tag;
    const engine = createEngine(b, optimize, target);

    const exe = b.addExecutable(.{
        .name = "simulo",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });
    setupExecutable(b, exe);
    exe.root_module.addImport("engine", engine);

    bundle(b, exe);
    if (usesVulkan(os)) {
        exe.step.dependOn(embedVkShader(b, "src/shader/text.vert"));
        exe.step.dependOn(embedVkShader(b, "src/shader/text.frag"));
        exe.step.dependOn(embedVkShader(b, "src/shader/model.vert"));
        exe.step.dependOn(embedVkShader(b, "src/shader/model.frag"));
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const build_tests = b.option(bool, "build-tests", "Build test executables") orelse false;
    if (build_tests) {
        const test_exe = b.addExecutable(.{
            .name = "simulo_test",
            .target = target,
            .optimize = optimize,
        });
        test_exe.addIncludePath(b.path("src"));
        test_exe.linkLibCpp();

        // Test files
        const test_files = [_][]const u8{
            "src/test_main.cc",
            "src/math/angle_test.cc",
            "src/math/matrix_test.cc",
            "src/math/vector_test.cc",
        };

        test_exe.addCSourceFiles(.{
            .files = &test_files,
            .flags = &[_][]const u8{"-std=c++20"},
        });

        test_exe.linkSystemLibrary("opencv4");
        test_exe.linkSystemLibrary("onnxruntime");
        test_exe.linkSystemLibrary("libdeflate");

        if (os == .macos) {
            test_exe.linkFramework("Foundation");
            test_exe.linkFramework("AppKit");
            test_exe.linkFramework("Metal");
            test_exe.linkFramework("QuartzCore");
        }

        b.installArtifact(test_exe);

        const test_run_cmd = b.addRunArtifact(test_exe);
        test_run_cmd.step.dependOn(b.getInstallStep());
        const test_run_step = b.step("test", "Run tests");
        test_run_step.dependOn(&test_run_cmd.step);

        // Perception test
        const perception_test = b.addExecutable(.{
            .name = "perception_test",
            .target = target,
            .optimize = optimize,
        });
        perception_test.addIncludePath(b.path("src"));
        perception_test.linkLibCpp();
        perception_test.addCSourceFile(.{
            .file = b.path("src/perception_test.cc"),
            .flags = &[_][]const u8{"-std=c++20"},
        });

        perception_test.linkSystemLibrary("opencv4");
        perception_test.linkSystemLibrary("onnxruntime");
        perception_test.linkSystemLibrary("libdeflate");

        if (os == .macos) {
            perception_test.linkFramework("Foundation");
            perception_test.linkFramework("AppKit");
            perception_test.linkFramework("Metal");
            perception_test.linkFramework("QuartzCore");
            perception_test.linkFramework("AVFoundation");
            perception_test.linkFramework("CoreImage");
            perception_test.linkFramework("CoreMedia");
            perception_test.linkFramework("CoreVideo");
        }

        b.installArtifact(perception_test);
    }
}

fn embedVkShader(b: *std.Build, comptime file: []const u8) *std.Build.Step {
    const out_file = file ++ ".spv";
    const run = b.addSystemCommand(&[_][]const u8{ "glslc", file, "-o", out_file });
    return &run.step;
}

fn bundle(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const bundle_step = b.step("bundle", "Create macOS .app bundle");

    const install_exe = b.addInstallArtifact(exe, .{
        .dest_dir = .{
            .override = .{
                .custom = "simulo.app/Contents/MacOS",
            },
        },
    });

    const install_plist = b.addInstallFile(b.path("src/res/Info.plist"), "simulo.app/Contents/Info.plist");

    const gen_air = b.addSystemCommand(&[_][]const u8{ "xcrun", "-sdk", "macosx", "metal", "-c", "src/shader/text.metal", "-o", "text.air" });
    const gen_metallib = b.addSystemCommand(&[_][]const u8{ "xcrun", "-sdk", "macosx", "metallib", "text.air", "-o", "default.metallib" });
    gen_metallib.step.dependOn(&gen_air.step);
    const install_metallib = b.addInstallFile(b.path("default.metallib"), "simulo.app/Contents/Resources/default.metallib");
    install_metallib.step.dependOn(&gen_metallib.step);

    bundle_step.dependOn(&install_exe.step);
    bundle_step.dependOn(&install_plist.step);
    bundle_step.dependOn(&install_metallib.step);

    b.default_step.dependOn(bundle_step);
}

fn createEngine(b: *std.Build, optimize: std.builtin.OptimizeMode, target: std.Build.ResolvedTarget) *std.Build.Module {
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
        "src/perception/perception.cc",
        "src/ttf/ttf.cc",
        "src/ui/font.cc",
        "src/ui/ui.cc",
        "src/util/rational.cc",
        "src/app.cc",
        "src/stl.cc",
    }) catch unreachable;

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
        //exe.bundle_compiler_rt = true;
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

    const use_vulkan = os == .windows or os == .linux;
    if (use_vulkan) {
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

    engine.linkSystemLibrary("opencv4", .{});
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
