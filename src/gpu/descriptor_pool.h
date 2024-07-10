#ifndef VILLA_GPU_DESCRIPTOR_POOL_H_
#define VILLA_GPU_DESCRIPTOR_POOL_H_

#include <vulkan/vulkan_core.h>

#include "gpu/buffer.h"
#include "gpu/image.h"

namespace villa {

class DescriptorPool {
public:
   DescriptorPool(
       VkDevice device, const std::vector<VkDescriptorSetLayoutBinding> &layouts, uint32_t num_sets
   );

   inline ~DescriptorPool() {
      vkDestroyDescriptorSetLayout(device_, descriptor_layout_, nullptr);
      vkDestroyDescriptorPool(device_, descriptor_pool_, nullptr);
   }

   VkDescriptorSet allocate(const UniformBuffer &buffer, const Image &image, VkSampler sampler);

   inline VkDescriptorSetLayout layout() const {
      return descriptor_layout_;
   }

private:
   VkDevice device_;
   VkDescriptorSetLayout descriptor_layout_;
   VkDescriptorPool descriptor_pool_;
};

} // namespace villa

#endif // !VILLA_GPU_DESCRIPTOR_POOL_H_
