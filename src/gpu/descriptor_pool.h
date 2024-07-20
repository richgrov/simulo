#ifndef VKAD_GPU_DESCRIPTOR_POOL_H_
#define VKAD_GPU_DESCRIPTOR_POOL_H_

#include <vulkan/vulkan_core.h>

#include "gpu/buffer.h"
#include "gpu/image.h"

namespace vkad {

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

   inline static VkDescriptorSetLayoutBinding uniform_buffer_dynamic(uint32_t binding) {
      return VkDescriptorSetLayoutBinding{
          .binding = binding,
          .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
          .descriptorCount = 1,
          .stageFlags = VK_SHADER_STAGE_VERTEX_BIT,
      };
   }

   inline static VkDescriptorSetLayoutBinding combined_image_sampler(uint32_t binding) {
      return VkDescriptorSetLayoutBinding{
          .binding = binding,
          .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
          .descriptorCount = 1,
          .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT,
      };
   }

private:
   VkDevice device_;
   VkDescriptorSetLayout descriptor_layout_;
   VkDescriptorPool descriptor_pool_;
};

} // namespace vkad

#endif // !VKAD_GPU_DESCRIPTOR_POOL_H_
