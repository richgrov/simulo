#include "buffer.h"

#include <cstring>
#include <vulkan/vulkan_core.h>

#include "physical_device.h"
#include "status.h"
#include "util/memory.h"

using namespace vkad;

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
   VKAD_VK(vkCreateBuffer(device, &create_info, nullptr, &buffer_));

   VkMemoryRequirements requirements;
   vkGetBufferMemoryRequirements(device, buffer_, &requirements);

   VkMemoryAllocateInfo alloc_info = {
       .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
       .allocationSize = requirements.size,
       .memoryTypeIndex =
           physical_device.find_memory_type_index(requirements.memoryTypeBits, memory_properties),
   };

   VKAD_VK(vkAllocateMemory(device, &alloc_info, nullptr, &allocation_));
   VKAD_VK(vkBindBufferMemory(device, buffer_, allocation_, 0));
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

StagingBuffer::StagingBuffer(
    VkDeviceSize capacity, VkDevice device, const PhysicalDevice &physical_device
)
    : Buffer(
          capacity, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
          static_cast<VkMemoryPropertyFlagBits>(
              VK_MEMORY_PROPERTY_HOST_COHERENT_BIT | VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
          ),
          device, physical_device
      ),
      capacity_(capacity), size_(0) {
   vkMapMemory(device, allocation_, 0, capacity, 0, &mem_map_);
}

void StagingBuffer::upload_mesh(
    void *vertices, size_t vertices_size, VertexIndexBuffer::IndexType *indices,
    VertexIndexBuffer::IndexType num_indices
) {
   VkDeviceSize indices_size = num_indices * sizeof(VertexIndexBuffer::IndexType);
   VkDeviceSize total_size = vertices_size + indices_size;
   size_ = total_size;

   std::memcpy(mem_map_, vertices, vertices_size);
   std::memcpy(reinterpret_cast<uint8_t *>(mem_map_) + vertices_size, indices, indices_size);
}

UniformBuffer::UniformBuffer(
    VkDeviceSize element_size, VkDeviceSize num_elements, VkDevice device,
    const PhysicalDevice &physical_device
)
    : Buffer(
          align_to(element_size, physical_device.min_uniform_alignment()) * num_elements,
          VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
          static_cast<VkMemoryPropertyFlagBits>(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT), device,
          physical_device
      ),
      element_size_(align_to(element_size, physical_device.min_uniform_alignment())) {

   vkMapMemory(device, allocation_, 0, element_size_ * num_elements, 0, &mem_map_);
}
