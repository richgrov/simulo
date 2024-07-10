#include "descriptor_pool.h"

#include <stdexcept>
#include <vulkan/vulkan_core.h>

#include "gpu/buffer.h"
#include "gpu/pipeline.h"
#include "gpu/status.h"
#include "util/memory.h"

using namespace villa;

DescriptorPool::DescriptorPool(VkDevice device, const Pipeline &pipeline)
    : device_(device), descriptor_layout_(pipeline.descriptor_set_layout()) {
   VkDescriptorPoolSize sizes[] = {
       {
           .type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
           .descriptorCount = 1,
       },
       {
           .type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
           .descriptorCount = 1,
       },
   };

   VkDescriptorPoolCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
       .maxSets = 1,
       .poolSizeCount = VILLA_ARRAY_LEN(sizes),
       .pPoolSizes = sizes,
   };

   if (vkCreateDescriptorPool(device, &create_info, nullptr, &descriptor_pool_) != VK_SUCCESS) {
      throw std::runtime_error("failed to create descriptor pool");
   }
}

VkDescriptorSet
DescriptorPool::allocate(const UniformBuffer &buffer, const Image &image, VkSampler sampler) {
   VkDescriptorSetAllocateInfo alloc_info = {
       .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
       .descriptorPool = descriptor_pool_,
       .descriptorSetCount = 1,
       .pSetLayouts = &descriptor_layout_,
   };

   VkDescriptorSet descriptor_set;
   VILLA_VK(vkAllocateDescriptorSets(device_, &alloc_info, &descriptor_set));

   VkDescriptorBufferInfo buf_info = {
       .buffer = buffer.buffer(),
       .offset = 0,
       .range = buffer.element_size(),
   };

   VkDescriptorImageInfo img_info = {
       .sampler = sampler,
       .imageView = image.view(),
       .imageLayout = image.layout(),
   };

   std::vector<VkWriteDescriptorSet> writes;
   writes.push_back({
       .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
       .dstSet = descriptor_set,
       .dstBinding = 0,
       .descriptorCount = 1,
       .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
       .pBufferInfo = &buf_info,
   });
   writes.push_back({
       .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
       .dstSet = descriptor_set,
       .dstBinding = 1,
       .descriptorCount = 1,
       .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
       .pImageInfo = &img_info,
   });

   vkUpdateDescriptorSets(device_, static_cast<uint32_t>(writes.size()), writes.data(), 0, nullptr);
   return descriptor_set;
}
