#ifndef VILLA_GPU_DESCRIPTOR_POOL_H_
#define VILLA_GPU_DESCRIPTOR_POOL_H_

#include <vulkan/vulkan_core.h>

#include "gpu/buffer.h"
#include "gpu/pipeline.h"

namespace villa {

class DescriptorPool {
public:
   DescriptorPool(VkDevice device, const Pipeline &pipeline);

   inline ~DescriptorPool() {
      vkDestroyDescriptorPool(device_, descriptor_pool_, nullptr);
   }

   VkDescriptorSet allocate(const UniformBuffer &buffer);

private:
   VkDevice device_;
   VkDescriptorSetLayout descriptor_layout_;
   VkDescriptorPool descriptor_pool_;
};

} // namespace villa

#endif // !VILLA_GPU_DESCRIPTOR_POOL_H_
