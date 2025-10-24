const std = @import("std");
const vk = @import("vulkan");

pub fn vkAssert(result: c_int) error{VulkanFailure}!void {
    if (result != vk.VK_SUCCESS) return error.VulkanFailure;
}
