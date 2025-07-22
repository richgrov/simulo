#pragma once

#include "physical_device.h"
#include "vulkan/vulkan_core.h"
#include <cstring>
#include <span>

namespace simulo {

typedef struct Buffer {
   VkBuffer buffer;
   VkDeviceMemory allocation;
   VkDevice device;
} Buffer;

void buffer_init(
    Buffer* buffer, size_t size, VkBufferUsageFlags usage, VkMemoryPropertyFlagBits memory_properties,
    VkDevice device, const PhysicalDevice &physical_device
);
void buffer_destroy(Buffer* buffer);
Buffer buffer_move(Buffer* other);
Buffer& buffer_move_assign(Buffer* self, Buffer* other);

typedef uint16_t IndexType;

typedef struct VertexIndexBuffer {
   Buffer buffer;
   size_t vertex_data_size;
   IndexType num_indices;
} VertexIndexBuffer;

void vertex_index_buffer_init(
    VertexIndexBuffer* vib, size_t vertex_data_size, IndexType num_indices, 
    VkDevice device, const PhysicalDevice &physical_device
);
void vertex_index_buffer_destroy(VertexIndexBuffer* vib);
IndexType vertex_index_buffer_num_indices(const VertexIndexBuffer* vib);
VkDeviceSize vertex_index_buffer_index_offset(const VertexIndexBuffer* vib);

class StagingBuffer {
public:
   explicit StagingBuffer(
       VkDeviceSize capacity, VkDevice device, const PhysicalDevice &physical_device
   );

   inline void upload_raw(void *data, size_t size) const {
      std::memcpy(mem_map_, data, size);
   }

   void upload_mesh(
       const std::span<uint8_t> vertex_data,
       const std::span<IndexType> index_data
   );

   inline VkDeviceSize capacity() const {
      return capacity_;
   }

   inline VkDeviceSize size() const {
      return size_;
   }

   inline VkBuffer buffer() const {
      return buffer_.buffer;
   }

private:
   Buffer buffer_;
   VkDeviceSize capacity_;
   VkDeviceSize size_;
   void *mem_map_;
};

class UniformBuffer {
public:
   explicit UniformBuffer(
       VkDeviceSize element_size, VkDeviceSize num_elements, VkDevice device,
       const PhysicalDevice &physical_device
   );

   UniformBuffer(UniformBuffer &&other);

   inline ~UniformBuffer() {
      bool buffer_was_moved = buffer_.allocation == nullptr;
      if (!buffer_was_moved) {
         vkUnmapMemory(buffer_.device, buffer_.allocation);
      }
   }

   inline void upload_memory(void *data, size_t size, size_t element_index) {
      uint8_t *start = reinterpret_cast<uint8_t *>(mem_map_) + element_index * element_size_;
      std::memcpy(start, data, size);
   }

   inline VkDeviceSize element_size() const {
      return element_size_;
   }

   inline VkBuffer buffer() const {
      return buffer_.buffer;
   }

private:
   Buffer buffer_;
   VkDeviceSize element_size_;
   void *mem_map_;
};

} // namespace simulo
