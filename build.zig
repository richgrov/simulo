const std = @import("std");
const builtin = @import("builtin");
const ArrayList = std.ArrayList;
const mem = std.mem;
const fs = std.fs;

// Build script for simulo project, converted from CMake to Zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const is_windows = target.result.os.tag == .windows;
    const is_macos = target.result.os.tag == .macos;
    const is_linux = target.result.os.tag == .linux;

    // Define a variable to indicate if we should use Vulkan
    const use_vulkan = is_windows or is_linux;

    // Create base exe
    const exe = b.addExecutable(.{
        .name = "simulo",
        .target = target,
        .optimize = optimize,
    });

    // Add test executable if build testing is enabled
    const build_tests = b.option(bool, "build-tests", "Build test executables") orelse false;

    // Add various flags
    if (optimize == .Debug) {
        exe.root_module.addCMacro("SIMULO_DEBUG", "");
        exe.root_module.addCMacro("VKAD_DEBUG", "");
    }

    // Set up common include directories
    exe.addIncludePath(b.path("src"));
    exe.linkLibCpp();

    // Add common source files
    var common_sources = ArrayList([]const u8).init(b.allocator);
    defer common_sources.deinit();

    // Base source files from CMakeLists.txt
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

    // Add platform-specific source files
    if (is_windows) {
        // Windows platform sources
        const windows_files = [_][]const u8{
            "src/window/win32/window.cc",
        };

        for (windows_files) |file| {
            common_sources.append(file) catch unreachable;
        }

        // Link to Vulkan
        exe.linkSystemLibrary("vulkan-1");
        exe.linkSystemLibrary("onnxruntime");
    } else if (is_macos) {
        // macOS platform sources
        const macos_files = [_][]const u8{
            "src/gpu/metal/buffer.mm",
            "src/gpu/metal/command_queue.mm",
            "src/gpu/metal/gpu.mm",
            "src/gpu/metal/image.mm",
            "src/gpu/metal/render_pipeline.mm",
            "src/render/mt_renderer.mm",
            "src/window/macos/window.mm",
        };

        for (macos_files) |file| {
            common_sources.append(file) catch unreachable;
        }

        // Link macOS frameworks
        exe.linkFramework("Foundation");
        exe.linkFramework("AppKit");
        exe.linkFramework("Metal");
        exe.linkFramework("QuartzCore");

        // Set bundle info
        exe.bundle_compiler_rt = true;
        exe.use_llvm = true;
        // Don't use LLD for macOS as it doesn't support Mach-O format
    } else if (is_linux) {
        // Linux platform sources
        const linux_files = [_][]const u8{
            "src/window/linux/wl_deleter.cc",
            "src/window/linux/wl_window.cc",
            "src/window/linux/x11_window.cc",
        };

        for (linux_files) |file| {
            common_sources.append(file) catch unreachable;
        }

        // Linux dependencies
        exe.linkSystemLibrary("vulkan");
        exe.linkSystemLibrary("X11");
        exe.linkSystemLibrary("Xi");
        exe.linkSystemLibrary("wayland-client");
        exe.linkSystemLibrary("wayland-protocols");
        exe.linkSystemLibrary("xkbcommon");

        // Generate Wayland protocol files (simplified, actual implementation will need a custom build step)
        // TODO: Implement generateWaylandProtocol function for Linux builds
    }

    // Add Vulkan sources if needed
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

        for (vulkan_files) |file| {
            common_sources.append(file) catch unreachable;
        }

        // Embed Vulkan shaders
        if (is_windows or is_linux) {
            // TODO: Implement embedVulkanShader function
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

    // Main source file
    exe.addCSourceFile(.{
        .file = b.path("src/main.cc"),
        .flags = &[_][]const u8{"-std=c++20"},
    });

    // OpenCV, ONNXRuntime, and libdeflate dependencies (simplified, actual implementation may need pkg-config)
    exe.linkSystemLibrary("opencv4");
    exe.linkSystemLibrary("onnxruntime");
    exe.linkSystemLibrary("libdeflate");

    // Set up the executable installation
    b.installArtifact(exe);

    // Run command - allows `zig build run`
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

        for (test_files) |file| {
            test_exe.addCSourceFile(.{
                .file = b.path(file),
                .flags = &[_][]const u8{"-std=c++20"},
            });
        }

        // Link with the common sources
        for (common_sources.items) |file| {
            if (std.mem.endsWith(u8, file, ".cc") or
                std.mem.endsWith(u8, file, ".c") or
                std.mem.endsWith(u8, file, ".mm"))
            {
                test_exe.addCSourceFile(.{
                    .file = b.path(file),
                    .flags = &[_][]const u8{"-std=c++20"},
                });
            }
        }

        test_exe.linkSystemLibrary("opencv4");
        test_exe.linkSystemLibrary("onnxruntime");
        test_exe.linkSystemLibrary("libdeflate");

        if (is_macos) {
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

        // Link with the common sources
        for (common_sources.items) |file| {
            if (std.mem.endsWith(u8, file, ".cc") or
                std.mem.endsWith(u8, file, ".c") or
                std.mem.endsWith(u8, file, ".mm"))
            {
                perception_test.addCSourceFile(.{
                    .file = b.path(file),
                    .flags = &[_][]const u8{"-std=c++20"},
                });
            }
        }

        perception_test.linkSystemLibrary("opencv4");
        perception_test.linkSystemLibrary("onnxruntime");
        perception_test.linkSystemLibrary("libdeflate");

        if (is_macos) {
            perception_test.linkFramework("Foundation");
            perception_test.linkFramework("AppKit");
            perception_test.linkFramework("Metal");
            perception_test.linkFramework("QuartzCore");
        }

        b.installArtifact(perception_test);
    }
}
