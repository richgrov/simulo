#include "descriptor_pool.h"

#include <stdexcept>
#include <vulkan/vulkan_core.h>

#include "gpu/buffer.h"
#include "gpu/status.h"
#include "util/memory.h"

using namespace vkad;

DescriptorPool::DescriptorPool(
    VkDevice device, const std::vector<VkDescriptorSetLayoutBinding> &layouts, uint32_t num_sets
)
    : device_(device) {

   VkDescriptorSetLayoutCreateInfo layout_create = {
       .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
       .bindingCount = static_cast<uint32_t>(layouts.size()),
       .pBindings = layouts.data(),
   };
   VKAD_VK(vkCreateDescriptorSetLayout(device, &layout_create, nullptr, &descriptor_layout_));

   std::vector<VkDescriptorPoolSize> sizes;
   sizes.reserve(layouts.size());
   for (const auto &layout : layouts) {
      sizes.push_back({
          .type = layout.descriptorType,
          .descriptorCount = layout.descriptorCount,
      });
   }

   VkDescriptorPoolCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
       .maxSets = num_sets,
       .poolSizeCount = static_cast<uint32_t>(sizes.size()),
       .pPoolSizes = sizes.data(),
   };
   VKAD_VK(vkCreateDescriptorPool(device, &create_info, nullptr, &descriptor_pool_));
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
   VKAD_VK(vkAllocateDescriptorSets(device_, &alloc_info, &descriptor_set));

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
