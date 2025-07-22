#include "buffer.h"

#include <cstring>
#include <vulkan/vulkan_core.h>

#include "physical_device.h"
#include "status.h"
#include "util/memory.h"

using namespace simulo;

void buffer_init(
    VkBuffer *buffer, VkDeviceMemory *allocation, size_t size, VkBufferUsageFlags usage,
    VkMemoryPropertyFlagBits memory_properties, VkDevice device,
    const PhysicalDevice &physical_device
) {
   VkBufferCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
       .size = size,
       .usage = usage,
       .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
   };
   VKAD_VK(vkCreateBuffer(device, &create_info, nullptr, buffer));

   VkMemoryRequirements requirements;
   vkGetBufferMemoryRequirements(device, *buffer, &requirements);

   VkMemoryAllocateInfo alloc_info = {
       .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
       .allocationSize = requirements.size,
       .memoryTypeIndex =
           physical_device.find_memory_type_index(requirements.memoryTypeBits, memory_properties),
   };

   VKAD_VK(vkAllocateMemory(device, &alloc_info, nullptr, allocation));
   VKAD_VK(vkBindBufferMemory(device, *buffer, *allocation, 0));
}

void buffer_destroy(VkBuffer *buffer, VkDeviceMemory *allocation, VkDevice device) {
   vkDestroyBuffer(device, *buffer, nullptr);
   vkFreeMemory(device, *allocation, nullptr);
}

void vertex_index_buffer_init(
    VertexIndexBuffer *vib, size_t vertex_data_size, IndexBufferType num_indices, VkDevice device,
    const PhysicalDevice &physical_device
) {
   size_t index_data_size = num_indices * sizeof(IndexBufferType);
   size_t total_size = vertex_data_size + index_data_size;

   buffer_init(
       &vib->buffer, &vib->allocation, total_size,
       static_cast<VkBufferUsageFlags>(
           VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT
       ),
       static_cast<VkMemoryPropertyFlagBits>(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT), device,
       physical_device
   );

   vib->vertex_data_size = vertex_data_size;
   vib->num_indices = num_indices;
}

StagingBuffer::StagingBuffer(
    VkDeviceSize capacity, VkDevice device, const PhysicalDevice &physical_device
)
    : capacity_(capacity), size_(0), device_(device) {

   buffer_init(
       &buffer_, &allocation_, capacity, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
       static_cast<VkMemoryPropertyFlagBits>(
           VK_MEMORY_PROPERTY_HOST_COHERENT_BIT | VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
       ),
       device, physical_device
   );
   vkMapMemory(device, allocation_, 0, capacity, 0, &mem_map_);
}

StagingBuffer::StagingBuffer(StagingBuffer &&other)
    : device_(other.device_),
      buffer_(other.buffer_),
      allocation_(other.allocation_),
      capacity_(other.capacity_),
      size_(other.size_),
      mem_map_(other.mem_map_) {
   other.device_ = VK_NULL_HANDLE;
   other.buffer_ = VK_NULL_HANDLE;
   other.allocation_ = VK_NULL_HANDLE;
   other.capacity_ = 0;
   other.size_ = 0;
   other.mem_map_ = nullptr;
}

void StagingBuffer::upload_mesh(
    const std::span<uint8_t> vertex_data, const std::span<IndexBufferType> index_data
) {
   size_ = vertex_data.size_bytes() + index_data.size_bytes();

   std::memcpy(mem_map_, vertex_data.data(), vertex_data.size_bytes());
   std::memcpy(
       reinterpret_cast<uint8_t *>(mem_map_) + vertex_data.size_bytes(), index_data.data(),
       index_data.size_bytes()
   );
}

UniformBuffer::UniformBuffer(
    VkDeviceSize element_size, VkDeviceSize num_elements, VkDevice device,
    const PhysicalDevice &physical_device
)
    : element_size_(align_to(element_size, physical_device.min_uniform_alignment())),
      device_(device) {

   buffer_init(
       &buffer_, &allocation_, element_size_ * num_elements, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
       static_cast<VkMemoryPropertyFlagBits>(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT), device,
       physical_device
   );

   vkMapMemory(device, allocation_, 0, element_size_ * num_elements, 0, &mem_map_);
}

UniformBuffer::UniformBuffer(UniformBuffer &&other)
    : device_(other.device_),
      buffer_(other.buffer_),
      allocation_(other.allocation_),
      element_size_(other.element_size_),
      mem_map_(other.mem_map_) {
   other.device_ = VK_NULL_HANDLE;
   other.buffer_ = VK_NULL_HANDLE;
   other.allocation_ = VK_NULL_HANDLE;
   other.element_size_ = 0;
   other.mem_map_ = nullptr;
}

UniformBuffer &UniformBuffer::operator=(UniformBuffer &&other) {
   buffer_destroy(&buffer_, &allocation_, device_);
   device_ = other.device_;
   buffer_ = other.buffer_;
   allocation_ = other.allocation_;
   element_size_ = other.element_size_;
   mem_map_ = other.mem_map_;
   return *this;
}
