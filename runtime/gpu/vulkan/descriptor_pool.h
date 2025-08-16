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

VkDescriptorPool create_descriptor_pool(
    VkDevice device, VkDescriptorSetLayout layout, const std::vector<VkDescriptorPoolSize> &sizes,
    uint32_t num_sets
);

void delete_descriptor_pool(VkDevice device, VkDescriptorPool pool);

VkDescriptorSet
allocate_descriptor_set(VkDevice device, VkDescriptorPool pool, VkDescriptorSetLayout layout);

void free_descriptor_set(VkDevice device, VkDescriptorPool pool, VkDescriptorSet set);

void write_descriptor_set(
    VkDevice device, VkDescriptorSet set, const std::vector<DescriptorWrite> &writes
);

DescriptorWrite write_uniform_buffer_dynamic(UniformBuffer &buf);

VkDescriptorSetLayoutBinding uniform_buffer_dynamic(uint32_t binding);

VkDescriptorSetLayoutBinding combined_image_sampler(uint32_t binding);

DescriptorWrite write_combined_image_sampler(VkSampler sampler, const Image &image);

} // namespace simulo
