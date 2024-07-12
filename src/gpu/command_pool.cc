#include "command_pool.h"

#include <vulkan/vulkan_core.h>

#include "status.h"

using namespace villa;

void CommandPool::init(VkDevice device, uint32_t graphics_queue_family) {
   device_ = device;

   VkCommandPoolCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
       .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
       .queueFamilyIndex = graphics_queue_family,
   };
   VILLA_VK(vkCreateCommandPool(device, &create_info, nullptr, &command_pool_));
}

void CommandPool::deinit() {
   if (command_pool_ != VK_NULL_HANDLE) {
      vkDestroyCommandPool(device_, command_pool_, nullptr);
   }
}

VkCommandBuffer CommandPool::allocate() {
   VkCommandBufferAllocateInfo alloc_info = {
       .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
       .commandPool = command_pool_,
       .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
       .commandBufferCount = 1,
   };

   VkCommandBuffer result;
   VILLA_VK(vkAllocateCommandBuffers(device_, &alloc_info, &result));

   return result;
}
