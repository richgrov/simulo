const std = @import("std");
const builtin = @import("builtin");
const ArrayList = std.ArrayList;
const mem = std.mem;
const fs = std.fs;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const os = target.result.os.tag;
    const use_vulkan = os == .windows or os == .linux;

    const exe = b.addExecutable(.{
        .name = "simulo",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });

    const build_tests = b.option(bool, "build-tests", "Build test executables") orelse false;

    if (optimize == .Debug) {
        exe.root_module.addCMacro("SIMULO_DEBUG", "");
        exe.root_module.addCMacro("VKAD_DEBUG", "");
    }

    exe.addIncludePath(b.path("src"));
    exe.linkLibCpp();

    var common_sources = ArrayList([]const u8).init(b.allocator);
    defer common_sources.deinit();

    const common_base_files = [_][]const u8{
        "src/entity/player.cc",
        "src/geometry/circle.cc",
        "src/geometry/model.cc",
        "src/geometry/shape.cc",
        "src/image/png.cc",
        "src/perception/perception.cc",
        "src/perception/pose_model.cc",
        "src/ttf/ttf.cc",
        "src/ui/font.cc",
        "src/ui/ui.cc",
        "src/util/rational.cc",
        "src/app.cc",
        "src/stl.cc",
    };

    for (common_base_files) |file| {
        common_sources.append(file) catch unreachable;
    }

    if (os == .windows) {
        common_sources.append("src/window/win32/window.cc") catch unreachable;
        exe.linkSystemLibrary("vulkan-1");
        exe.linkSystemLibrary("onnxruntime");
    } else if (os == .macos) {
        const macos_files = [_][]const u8{
            "src/gpu/metal/buffer.mm",
            "src/gpu/metal/command_queue.mm",
            "src/gpu/metal/gpu.mm",
            "src/gpu/metal/image.mm",
            "src/gpu/metal/render_pipeline.mm",
            "src/render/mt_renderer.mm",
            "src/window/macos/window.mm",
        };

        common_sources.appendSlice(&macos_files) catch unreachable;

        exe.linkFramework("Foundation");
        exe.linkFramework("AppKit");
        exe.linkFramework("Metal");
        exe.linkFramework("QuartzCore");

        exe.bundle_compiler_rt = true;
        bundle(b, exe);
    } else if (os == .linux) {
        const linux_files = [_][]const u8{
            "src/window/linux/wl_deleter.cc",
            "src/window/linux/wl_window.cc",
            "src/window/linux/x11_window.cc",
        };

        common_sources.appendSlice(&linux_files) catch unreachable;

        exe.linkSystemLibrary("vulkan");
        exe.linkSystemLibrary("X11");
        exe.linkSystemLibrary("Xi");
        exe.linkSystemLibrary("wayland-client");
        exe.linkSystemLibrary("wayland-protocols");
        exe.linkSystemLibrary("xkbcommon");
    }

    if (use_vulkan) {
        const vulkan_files = [_][]const u8{
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
        };

        common_sources.appendSlice(&vulkan_files) catch unreachable;

        const vulkan_shaders = [_][]const u8{
            "src/shader/text.vert",
            "src/shader/text.frag",
            "src/shader/model.vert",
            "src/shader/model.frag",
        };

        for (vulkan_shaders) |_| {
            //const shader_step = embedVulkanShader(b, exe, shader);
            //exe.step.dependOn(&shader_step.step);
        }
    }

    // Add common binary resources
    //const arial_embed_step = embedBinary(b, exe, "src/res/arial.ttf"); exe.step.dependOn(&arial_embed_step.step);

    // Add model embedding
    //const model_embed_step = embedModel(b, exe, "yolo11n-pose"); exe.step.dependOn(&model_embed_step.step);

    // Add the source files to the executable
    exe.addCSourceFiles(.{
        .files = common_sources.items,
        .flags = &[_][]const u8{
            "-std=c++20",
        },
    });

    exe.linkSystemLibrary("opencv4");
    exe.linkSystemLibrary("onnxruntime");
    exe.linkSystemLibrary("libdeflate");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Test executable if enabled
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

        test_exe.addCSourceFiles(.{
            .files = common_sources.items,
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

        perception_test.addCSourceFiles(.{
            .files = common_sources.items,
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
        }

        b.installArtifact(perception_test);
    }
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
