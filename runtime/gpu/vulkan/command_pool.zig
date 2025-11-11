const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const vk = @import("vulkan");
const vkAssert = @import("status.zig").vkAssert;

pub const CommandPool = struct {
    device: vk.VkDevice,
    command_pool: vk.VkCommandPool,

    const Self = @This();

    pub fn init(device: vk.VkDevice, graphics_queue_family: u32) Self {
        const create_info = vk.VkCommandPoolCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = graphics_queue_family,
        };
        var command_pool: vk.VkCommandPool = null;
        vk.vkCreateCommandPool(device, &create_info, null, &command_pool);

        return .{ .device = device, .command_pool = command_pool };
    }

    pub fn allocate(self: *Self) error{VulkanFailure}!vk.VkCommandBuffer {
        const buffer_alloc_info = vk.VkCommandBufferAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandBufferCount = 1,
            .commandPool = self.command_pool,
            .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        };
        var command_buffer: vk.VkCommandBuffer = null;
        try vkAssert(vk.vkAllocateCommandBuffers(self.device, &buffer_alloc_info, &command_buffer));

        return command_buffer;
    }
};
