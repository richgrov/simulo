#pragma once

#include <cstdint>

#include <vulkan/vulkan_core.h>

namespace vkad {

class CommandPool {
public:
   CommandPool() : command_pool_(VK_NULL_HANDLE) {}

   CommandPool(const CommandPool &other) = delete;
   CommandPool &operator=(const CommandPool &other) = delete;

   void init(VkDevice device, uint32_t graphics_queue_family);

   void deinit();

   VkCommandBuffer allocate();

private:
   VkDevice device_;
   VkCommandPool command_pool_;
};

} // namespace vkad
