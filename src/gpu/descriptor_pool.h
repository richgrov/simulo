#ifndef VKAD_GPU_DESCRIPTOR_POOL_H_
#define VKAD_GPU_DESCRIPTOR_POOL_H_

#include <vulkan/vulkan_core.h>

#include "gpu/buffer.h"
#include "gpu/image.h"

namespace vkad {

struct DescriptorWrite {
   union {
      VkDescriptorImageInfo image_info;
      VkDescriptorBufferInfo buffer_info;
   };
   VkWriteDescriptorSet write;
};

class DescriptorPool {
public:
   DescriptorPool(
       VkDevice device, const std::vector<VkDescriptorSetLayoutBinding> &layouts, uint32_t num_sets
   );

   inline ~DescriptorPool() {
      vkDestroyDescriptorSetLayout(device_, descriptor_layout_, nullptr);
      vkDestroyDescriptorPool(device_, descriptor_pool_, nullptr);
   }

   VkDescriptorSet allocate();

   void write(VkDescriptorSet set, const std::vector<DescriptorWrite> &writes);

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

   inline static DescriptorWrite write_uniform_buffer_dynamic(UniformBuffer &buf) {
      DescriptorWrite write = {
          .buffer_info =
              {
                  .buffer = buf.buffer(),
                  .offset = 0,
                  .range = buf.element_size(),
              },
          .write =
              {
                  .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                  .dstBinding = 0,
                  .descriptorCount = 1,
                  .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
                  .pBufferInfo = &write.buffer_info,
              },
      };
      return write;
   }

   inline static DescriptorWrite
   write_combined_image_sampler(VkSampler sampler, const Image &image) {
      DescriptorWrite write = {
          .image_info =
              {
                  .sampler = sampler,
                  .imageView = image.view(),
                  .imageLayout = image.layout(),
              },
          .write =
              {
                  .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                  .dstBinding = 1,
                  .descriptorCount = 1,
                  .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                  .pImageInfo = &write.image_info,
              },
      };
      return write;
   }

private:
   VkDevice device_;
   VkDescriptorSetLayout descriptor_layout_;
   VkDescriptorPool descriptor_pool_;
};

} // namespace vkad

#endif // !VKAD_GPU_DESCRIPTOR_POOL_H_
