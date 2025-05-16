#pragma once

#include <vector>

#include <vulkan/vulkan_core.h>

#include "buffer.h"
#include "image.h"

namespace simulo {

struct DescriptorWrite {
   union {
      VkDescriptorImageInfo image_info;
      VkDescriptorBufferInfo buffer_info;
   };
   VkWriteDescriptorSet write;
};

class DescriptorPool {
public:
   explicit DescriptorPool(
       VkDevice device, VkDescriptorSetLayout layout,
       const std::vector<VkDescriptorPoolSize> &sizes, uint32_t num_sets
   );

   explicit inline DescriptorPool(DescriptorPool &&other) {
      device_ = other.device_;
      descriptor_pool_ = other.descriptor_pool_;
      other.descriptor_pool_ = VK_NULL_HANDLE;
   }

   explicit DescriptorPool(const DescriptorPool &other) = delete;

   inline ~DescriptorPool() {
      if (descriptor_pool_ != VK_NULL_HANDLE) {
         vkDestroyDescriptorPool(device_, descriptor_pool_, nullptr);
      }
   }

   DescriptorPool &operator=(const DescriptorPool &other) = delete;

   VkDescriptorSet allocate(VkDescriptorSetLayout layout);

   void write(VkDescriptorSet set, const std::vector<DescriptorWrite> &writes);

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
   VkDescriptorPool descriptor_pool_;
};

} // namespace simulo
