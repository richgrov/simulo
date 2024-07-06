#include "buffer.h"
#include "gpu/physical_device.h"
#include "vulkan/vulkan_core.h"

#include <cstring>
#include <format>
#include <stdexcept>
#include <vulkan/vulkan.h>

using namespace villa;

namespace {

uint32_t find_memory_type_index(
    const PhysicalDevice &physical_device, uint32_t supported_bits, VkMemoryPropertyFlagBits extra
) {
   VkPhysicalDeviceMemoryProperties properties;
   vkGetPhysicalDeviceMemoryProperties(physical_device.handle(), &properties);

   VkMemoryType mem_type;
   for (int i = 0; i < properties.memoryTypeCount; ++i) {
      bool supports_mem_type = (supported_bits & (1 << i)) != 0;
      bool supports_extra = (properties.memoryTypes[i].propertyFlags & extra) == extra;
      if (supports_mem_type && supports_extra) {
         return i;
      }
   }

   throw std::runtime_error(std::format(
       "no suitable memory type for bits {} and extra flags {}", supported_bits, (int)extra
   ));
}

} // namespace

Buffer::Buffer(
    size_t size, VkBufferUsageFlags usage, VkMemoryPropertyFlagBits memory_properties,
    VkDevice device, const PhysicalDevice &physical_device
)
    : buffer_(VK_NULL_HANDLE), device_(device) {
   VkBufferCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
       .size = size,
       .usage = usage,
       .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
   };

   if (vkCreateBuffer(device, &create_info, nullptr, &buffer_) != VK_SUCCESS) {
      throw std::runtime_error("failed to create buffer");
   }

   VkMemoryRequirements requirements;
   vkGetBufferMemoryRequirements(device, buffer_, &requirements);

   VkMemoryAllocateInfo alloc_info = {
       .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
       .allocationSize = requirements.size,
       .memoryTypeIndex =
           find_memory_type_index(physical_device, requirements.memoryTypeBits, memory_properties),
   };

   if (vkAllocateMemory(device, &alloc_info, nullptr, &allocation_) != VK_SUCCESS) {
      throw std::runtime_error("failed to allocate memory");
   }

   if (vkBindBufferMemory(device, buffer_, allocation_, 0) != VK_SUCCESS) {
      throw std::runtime_error("failed to bind memory buffer");
   }
}

Buffer &Buffer::operator=(Buffer &&other) {
   vkDestroyBuffer(device_, buffer_, nullptr);
   vkFreeMemory(device_, allocation_, nullptr);

   buffer_ = other.buffer_;
   allocation_ = other.allocation_;
   device_ = other.device_;
   other.buffer_ = VK_NULL_HANDLE;
   other.allocation_ = VK_NULL_HANDLE;
   other.device_ = VK_NULL_HANDLE;
   return *this;
}

void StagingBuffer::upload_mesh(
    void *vertices, size_t vertices_size, VertexIndexBuffer::IndexType *indices,
    VertexIndexBuffer::IndexType num_indices
) {
   VkDeviceSize indices_size = num_indices * sizeof(VertexIndexBuffer::IndexType);
   VkDeviceSize total_size = vertices_size + indices_size;
   size_ = total_size;

   void *cpy_dst;
   vkMapMemory(device_, allocation_, 0, total_size, 0, &cpy_dst);
   std::memcpy(cpy_dst, vertices, vertices_size);
   std::memcpy(reinterpret_cast<uint8_t *>(cpy_dst) + vertices_size, indices, indices_size);
   vkUnmapMemory(device_, allocation_);
}

UniformBuffer::UniformBuffer(
    VkDeviceSize capacity, VkDevice device, const PhysicalDevice &physical_device
)
    : Buffer(
          capacity, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
          static_cast<VkMemoryPropertyFlagBits>(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT), device,
          physical_device
      ) {

   vkMapMemory(device, allocation_, 0, capacity, 0, &mem_map_);
}
