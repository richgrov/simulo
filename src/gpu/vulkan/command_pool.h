#ifndef VKAD_GPU_VULKAN_COMMAND_POOL_H_
#define VKAD_GPU_VULKAN_COMMAND_POOL_H_

#include <cstdint>

#include <vulkan/vulkan_core.h>

namespace vkad {

class CommandPool {
public:
   CommandPool() : command_pool_(VK_NULL_HANDLE) {}

   void init(VkDevice device, uint32_t graphics_queue_family);

   void deinit();

   VkCommandBuffer allocate();

private:
   VkDevice device_;
   VkCommandPool command_pool_;
};

} // namespace vkad

#endif // !VKAD_GPU_VULKAN_COMMAND_POOL_H_
