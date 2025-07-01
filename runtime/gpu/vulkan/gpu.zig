const std = @import("std");
const builtin = @import("builtin");

const vk = @cImport({
    @cInclude("vulkan/vulkan_core.h");
});

const zig_util = @import("util.zig");

const validation_layers = [_][*c]const u8{
    "VK_LAYER_KHRONOS_validation",
};

fn validationLayersSupported(allocator: std.mem.Allocator) !bool {
    var total_layers: u32 = undefined;
    var status = vk.vkEnumerateInstanceLayerProperties(&total_layers, null);
    try zig_util.translateVkError(status);

    var layers = std.ArrayList(vk.VkLayerProperties).init(allocator);
    defer layers.deinit();
    try layers.resize(@intCast(total_layers));

    status = vk.vkEnumerateInstanceLayerProperties(&total_layers, @ptrCast(layers.items));
    try zig_util.translateVkError(status);

    var found = [_]bool{false} ** validation_layers.len;

    for (layers.items) |layer| {
        for (validation_layers, 0..) |validation_layer, i| {
            if (std.mem.orderZ(u8, @ptrCast(&layer.layerName), validation_layer) == .eq) {
                found[i] = true;
                break;
            }
        }
    }

    for (found) |layer_found| {
        if (!layer_found) return false;
    }

    return true;
}

pub const Gpu = struct {
    instance: vk.VkInstance,

    pub fn init(allocator: std.mem.Allocator) !Gpu {
        var instance: vk.VkInstance = undefined;

        const extensions = [_][*c]const u8{
            "VK_KHR_surface",
            switch (comptime builtin.os.tag) {
                .windows => "VK_KHR_win32_surface",
                .macos => "VK_KHR_metal_surface",
                .linux => if (try zig_util.isWayland(allocator)) "VK_KHR_wayland_surface" else "VK_KHR_xlib_surface",
                else => void,
            },
            if (builtin.os.tag == .macos) "VK_KHR_portability_enumeration" else void,
            if (builtin.os.tag == .macos) "VK_KHR_get_physical_device_properties2" else void,
        };

        if (comptime builtin.mode == .Debug) {
            if (!try validationLayersSupported(allocator)) {
                return error.ValidationNotSupported;
            }
        }

        const status = vk.vkCreateInstance(&vk.VkInstanceCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &vk.VkApplicationInfo{
                .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
                .applicationVersion = vk.VK_MAKE_VERSION(1, 0, 0),
                .engineVersion = vk.VK_MAKE_VERSION(1, 0, 0),
                .apiVersion = vk.VK_API_VERSION_1_0,
            },
            .flags = if (builtin.os.tag == .macos) vk.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR else 0,
            .enabledExtensionCount = @intCast(extensions.len),
            .ppEnabledExtensionNames = &extensions,
            .enabledLayerCount = if (builtin.mode == .Debug) @intCast(validation_layers.len) else 0,
            .ppEnabledLayerNames = if (builtin.mode == .Debug) &validation_layers else null,
        }, null, &instance);
        try zig_util.translateVkError(status);

        return .{ .instance = instance };
    }

    pub fn deinit(self: *Gpu) void {
        vk.vkDestroyInstance(self.instance, null);
    }
};
