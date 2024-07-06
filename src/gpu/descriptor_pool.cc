#include "descriptor_pool.h"

#include <stdexcept>
#include <vulkan/vulkan_core.h>

#include "gpu/buffer.h"
#include "gpu/pipeline.h"

using namespace villa;

DescriptorPool::DescriptorPool(VkDevice device, const Pipeline &pipeline)
    : device_(device), descriptor_layout_(pipeline.descriptor_set_layout()) {
   VkDescriptorPoolSize size = {
       .type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
       .descriptorCount = 1,
   };

   VkDescriptorPoolCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
       .maxSets = 1,
       .poolSizeCount = 1,
       .pPoolSizes = &size,
   };

   if (vkCreateDescriptorPool(device, &create_info, nullptr, &descriptor_pool_) != VK_SUCCESS) {
      throw std::runtime_error("failed to create descriptor pool");
   }
}

VkDescriptorSet DescriptorPool::allocate(const UniformBuffer &buffer) {
   VkDescriptorSetAllocateInfo alloc_info = {
       .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
       .descriptorPool = descriptor_pool_,
       .descriptorSetCount = 1,
       .pSetLayouts = &descriptor_layout_,
   };

   VkDescriptorSet descriptor_set;
   if (vkAllocateDescriptorSets(device_, &alloc_info, &descriptor_set) != VK_SUCCESS) {
      throw std::runtime_error("failed to allocate descriptor set");
   }

   VkDescriptorBufferInfo buf_info = {
       .buffer = buffer.buffer(),
       .offset = 0,
       .range = buffer.element_size(),
   };

   VkWriteDescriptorSet desc_write = {
       .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
       .dstSet = descriptor_set,
       .dstBinding = 0,
       .descriptorCount = 1,
       .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
       .pBufferInfo = &buf_info,
   };

   vkUpdateDescriptorSets(device_, 1, &desc_write, 0, nullptr);
   return descriptor_set;
}
