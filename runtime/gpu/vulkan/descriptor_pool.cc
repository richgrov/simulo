#include "descriptor_pool.h"

#include <vulkan/vulkan_core.h>

#include "status.h"

using namespace simulo;

VkDescriptorPool simulo::create_descriptor_pool(
    VkDevice device, VkDescriptorSetLayout layout, const std::vector<VkDescriptorPoolSize> &sizes,
    uint32_t num_sets
) {
   VkDescriptorPoolCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
       .maxSets = num_sets,
       .poolSizeCount = static_cast<uint32_t>(sizes.size()),
       .pPoolSizes = sizes.data(),
   };

   VkDescriptorPool result;
   VKAD_VK(vkCreateDescriptorPool(device, &create_info, nullptr, &result));
   return result;
}

void simulo::delete_descriptor_pool(VkDevice device, VkDescriptorPool pool) {
   vkDestroyDescriptorPool(device, pool, nullptr);
}

VkDescriptorSet simulo::allocate_descriptor_set(
    VkDevice device, VkDescriptorPool pool, VkDescriptorSetLayout layout
) {
   VkDescriptorSetAllocateInfo alloc_info = {
       .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
       .descriptorPool = pool,
       //.descriptorSetLayout = layout,
       .descriptorSetCount = 1,
       .pSetLayouts = &layout,
   };

   VkDescriptorSet descriptor_set;
   VKAD_VK(vkAllocateDescriptorSets(device, &alloc_info, &descriptor_set));
   return descriptor_set;
}

void simulo::free_descriptor_set(VkDevice device, VkDescriptorPool pool, VkDescriptorSet set) {
   vkFreeDescriptorSets(device, pool, 1, &set);
}

void simulo::write_descriptor_set(
    VkDevice device, VkDescriptorSet set, const std::vector<DescriptorWrite> &writes
) {
   std::vector<VkWriteDescriptorSet> write_commands(writes.size());
   for (int i = 0; i < writes.size(); ++i) {
      write_commands[i] = writes[i].write;
      write_commands[i].dstSet = set;
   }

   vkUpdateDescriptorSets(
       device, static_cast<uint32_t>(write_commands.size()), write_commands.data(), 0, nullptr
   );
}

DescriptorWrite simulo::write_uniform_buffer_dynamic(UniformBuffer &buf) {
   DescriptorWrite write = {
       .buffer_info =
           {
               .buffer = buf.buffer(),
               .offset = 0,
               .range = buf.element_size(),
           },
       .write = {
           .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
           .dstBinding = 0,
           .descriptorCount = 1,
           .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
           .pBufferInfo = &write.buffer_info,
       },
   };
   return write;
}

VkDescriptorSetLayoutBinding simulo::uniform_buffer_dynamic(uint32_t binding) {
   return VkDescriptorSetLayoutBinding{
       .binding = binding,
       .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
       .descriptorCount = 1,
       .stageFlags = VK_SHADER_STAGE_VERTEX_BIT,
   };
}

VkDescriptorSetLayoutBinding simulo::combined_image_sampler(uint32_t binding) {
   return VkDescriptorSetLayoutBinding{
       .binding = binding,
       .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
       .descriptorCount = 1,
       .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT,
   };
}

DescriptorWrite simulo::write_combined_image_sampler(VkSampler sampler, const Image &image) {
   DescriptorWrite write = {
       .image_info =
           {
               .sampler = sampler,
               .imageView = image.view(),
               .imageLayout = image.layout(),
           },
       .write = {
           .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
           .dstBinding = 1,
           .descriptorCount = 1,
           .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
           .pImageInfo = &write.image_info,
       },
   };
   return write;
}
