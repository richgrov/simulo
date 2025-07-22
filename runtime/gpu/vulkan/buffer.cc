#include "buffer.h"

#include <cstring>
#include <vulkan/vulkan_core.h>

#include "physical_device.h"
#include "status.h"
#include "util/memory.h"

using namespace simulo;

void buffer_init(
    Buffer* buffer, size_t size, VkBufferUsageFlags usage, VkMemoryPropertyFlagBits memory_properties,
    VkDevice device, const PhysicalDevice &physical_device
) {
   buffer->buffer = VK_NULL_HANDLE;
   buffer->device = device;
   
   VkBufferCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
       .size = size,
       .usage = usage,
       .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
   };
   VKAD_VK(vkCreateBuffer(device, &create_info, nullptr, &buffer->buffer));

   VkMemoryRequirements requirements;
   vkGetBufferMemoryRequirements(device, buffer->buffer, &requirements);

   VkMemoryAllocateInfo alloc_info = {
       .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
       .allocationSize = requirements.size,
       .memoryTypeIndex =
           physical_device.find_memory_type_index(requirements.memoryTypeBits, memory_properties),
   };

   VKAD_VK(vkAllocateMemory(device, &alloc_info, nullptr, &buffer->allocation));
   VKAD_VK(vkBindBufferMemory(device, buffer->buffer, buffer->allocation, 0));
}

void buffer_destroy(Buffer* buffer) {
   vkDestroyBuffer(buffer->device, buffer->buffer, nullptr);
   vkFreeMemory(buffer->device, buffer->allocation, nullptr);
   buffer->buffer = VK_NULL_HANDLE;
   buffer->allocation = VK_NULL_HANDLE;
   buffer->device = VK_NULL_HANDLE;
}

Buffer buffer_move(Buffer* other) {
   Buffer result = *other;
   other->buffer = VK_NULL_HANDLE;
   other->allocation = VK_NULL_HANDLE;
   other->device = VK_NULL_HANDLE;
   return result;
}

Buffer& buffer_move_assign(Buffer* self, Buffer* other) {
   buffer_destroy(self);
   *self = *other;
   other->buffer = VK_NULL_HANDLE;
   other->allocation = VK_NULL_HANDLE;
   other->device = VK_NULL_HANDLE;
   return *self;
}

void vertex_index_buffer_init(
    VertexIndexBuffer* vib, size_t vertex_data_size, IndexType num_indices,
    VkDevice device, const PhysicalDevice &physical_device
) {
   size_t index_data_size = num_indices * sizeof(IndexType);
   size_t total_size = vertex_data_size + index_data_size;
   
   buffer_init(
       &vib->buffer, total_size,
       static_cast<VkBufferUsageFlags>(VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT),
       static_cast<VkMemoryPropertyFlagBits>(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
       device, physical_device
   );
   
   vib->vertex_data_size = vertex_data_size;
   vib->num_indices = num_indices;
}

void vertex_index_buffer_destroy(VertexIndexBuffer* vib) {
   buffer_destroy(&vib->buffer);
   vib->vertex_data_size = 0;
   vib->num_indices = 0;
}

IndexType vertex_index_buffer_num_indices(const VertexIndexBuffer* vib) {
   return vib->num_indices;
}

VkDeviceSize vertex_index_buffer_index_offset(const VertexIndexBuffer* vib) {
   return vib->vertex_data_size;
}

StagingBuffer::StagingBuffer(
    VkDeviceSize capacity, VkDevice device, const PhysicalDevice &physical_device
)
    : capacity_(capacity),
      size_(0) {
   buffer_init(
       &buffer_, capacity, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
       static_cast<VkMemoryPropertyFlagBits>(
           VK_MEMORY_PROPERTY_HOST_COHERENT_BIT | VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
       ),
       device, physical_device
   );
   vkMapMemory(device, buffer_.allocation, 0, capacity, 0, &mem_map_);
}

void StagingBuffer::upload_mesh(
    const std::span<uint8_t> vertex_data, const std::span<IndexType> index_data
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
    : element_size_(align_to(element_size, physical_device.min_uniform_alignment())) {
   
   buffer_init(
       &buffer_, element_size_ * num_elements,
       VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
       static_cast<VkMemoryPropertyFlagBits>(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT), device,
       physical_device
   );

   vkMapMemory(device, buffer_.allocation, 0, element_size_ * num_elements, 0, &mem_map_);
}

UniformBuffer::UniformBuffer(UniformBuffer &&other)
    : buffer_(buffer_move(&other.buffer_)), element_size_(other.element_size_), mem_map_(other.mem_map_) {
   other.element_size_ = 0;
   other.mem_map_ = nullptr;
}
