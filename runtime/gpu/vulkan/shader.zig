const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const vk = @import("vulkan");
const vkAssert = @import("status.zig").vkAssert;

pub const Shader = struct {
    device: vk.VkDevice,
    module: vk.VkShaderModule,

    const Self = @This();

    pub fn init(device: vk.VkDevice, comptime shader_code: []const u8) Self {
        const create_info = vk.VkShaderModuleCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .codeSize = shader_code.len,
            .pCode = shader_code.ptr,
        };
        var shader_module: vk.VkShaderModule = null;
        vkAssert(vk.vkCreateShaderModule(device, &create_info, null, &shader_module)) catch
            @panic("Failed to create shader module");

        return .{ .device = device, .module = shader_module };
    }

    pub fn deinit(self: *Self) void {
        vk.vkDestroyShaderModule(self.device, self.module, null);
    }
};
