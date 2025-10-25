const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const vkAssert = @import("status.zig").vkAssert;

pub const Surface = struct {
    surface: vk.VkSurfaceKHR = null,

    const Self = @This();

    pub fn init(instance: vk.VkInstance) Self {
        var surface = vk.VkSurfaceKHR{};
        var create_result: c_int = vk.VK_ERROR_INITIALIZATION_FAILED;

        switch (builtin.os.tag) {
            .windows => {
                const create_info = vk.VkWin32SurfaceCreateInfoKHR{
                    .sType = vk.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
                };

                create_result = vk.vkCreateWin32SurfaceKHR(instance, &create_info, null, &surface);
            },
            .macos => {
                const create_info = vk.VkMetalSurfaceCreateInfoEXT{
                    .sType = vk.VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT,
                };

                create_result = vk.vkCreateMetalSurfaceEXT(instance, &create_info, null, &surface);
            },
            .linux => {
                const create_info = vk.VkWaylandSurfaceCreateInfoKHR{
                    .sType = vk.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
                };

                create_result = vk.vkCreateWaylandSurfaceKHR(instance, &create_info, null, &surface);
            },
            else => |os| std.debug.panic("OS not supported for creating a window surface ({})\n", .{os}),
        }

        vkAssert(create_result) catch std.debug.panic(
            "Failed to Create window surface for {any} with error {}\n",
            .{ builtin.os.tag, create_result },
        );
        return .{ .surface = surface };
    }

    pub fn deinit(self: Self, instance: vk.VkInstance) void {
        vk.vkDestroySurfaceKHR(instance, self.surface, null);
    }

    pub fn getSurfaceSupport(self: Self, physical_device: vk.VkPhysicalDevice, family_index: u32) bool {
        var supported = false;
        var error_result = vk.VK_ERROR_FEATURE_NOT_PRESENT;
        switch (builtin.os.tag) {
            .windows => {
                supported = vk.vkGetPhysicalDeviceWin32PresentationSupportKHR(physical_device, family_index);
                error_result = vk.VK_SUCCESS;
            },
            .macos => error_result = vk.vkGetPhysicalDeviceSurfaceSupportKHR(
                physical_device,
                family_index,
                self.surface,
                &supported,
            ),
            .linux => {
                supported = vk.vkGetPhysicalDeviceWaylandPresentationSupportKHR(physical_device, family_index, self.surface);
                error_result = vk.VK_SUCCESS;
            },
            else => |os| std.debug.panic("OS not supported {any}\n", .{os}),
        }

        vkAssert(error_result) catch std.debug.panic("Could not find surface support: {}\n", .{error_result});
        return supported;
    }
};
