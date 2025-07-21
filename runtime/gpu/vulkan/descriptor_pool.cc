#include "descriptor_pool.h"

#include <vulkan/vulkan_core.h>

#include "status.h"

using namespace simulo;

VkDescriptorPool create_descriptor_pool(
    VkDevice device, VkDescriptorSetLayout layout, const std::vector<VkDescriptorPoolSize> &sizes,
    uint32_t num_sets
)
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

void delete_descriptor_pool(VkDevice device, VkDescriptorPool pool) {
   vkDestroyDescriptorPool(device, pool, nullptr);
}

VkDescriptorSet allocate_descriptor_set(VkDevice device, VkDescriptorPool pool, VkDescriptorSetLayout layout) {
   VkDescriptorSetAllocateInfo alloc_info = {
       .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
       .descriptorPool = pool,
       .descriptorSetCount = 1,
       .pSetLayouts = &layout,
   };

   VkDescriptorSet descriptor_set;
   VKAD_VK(vkAllocateDescriptorSets(device, &alloc_info, &descriptor_set));
   return descriptor_set;
}

void write_descriptor_set(VkDevice device, VkDescriptorSet set, const std::vector<DescriptorWrite> &writes) {
   std::vector<VkWriteDescriptorSet> write_commands(writes.size());
   for (int i = 0; i < writes.size(); ++i) {
      write_commands[i] = writes[i].write;
      write_commands[i].dstSet = set;
   }

   vkUpdateDescriptorSets(
       device, static_cast<uint32_t>(write_commands.size()), write_commands.data(), 0, nullptr
   );
}
