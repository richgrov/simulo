#ifndef VKAD_GPU_BUFFER_H_
#define VKAD_GPU_BUFFER_H_

#include "physical_device.h"
#include "vulkan/vulkan_core.h"
#include <cstring>
#include <span>

namespace vkad {

class Buffer {
public:
   explicit Buffer(
       size_t size, VkBufferUsageFlags usage, VkMemoryPropertyFlagBits memory_properties,
       VkDevice device, const PhysicalDevice &physical_device
   );

   Buffer(Buffer &&other)
       : allocation_(other.allocation_), device_(other.device_), buffer_(other.buffer_) {

      other.allocation_ = VK_NULL_HANDLE;
      other.buffer_ = VK_NULL_HANDLE;
   }

   Buffer(const Buffer &other) = delete;

   inline ~Buffer() {
      if (buffer_ != VK_NULL_HANDLE) {
         vkDestroyBuffer(device_, buffer_, nullptr);
      }

      if (allocation_ != VK_NULL_HANDLE) {
         vkFreeMemory(device_, allocation_, nullptr);
      }
   }

   Buffer &operator=(const Buffer &other) = delete;

   Buffer &operator=(Buffer &&other);

   inline VkBuffer buffer() const {
      return buffer_;
   }

protected:
   VkDeviceMemory allocation_;
   VkDevice device_;

private:
   VkBuffer buffer_;
};

class VertexIndexBuffer : public Buffer {
public:
   using IndexType = uint16_t;

   explicit inline VertexIndexBuffer(
       size_t vertex_data_size, IndexType num_indices, VkDevice device,
       const PhysicalDevice &physical_device
   )
       : Buffer(
             vertex_data_size + num_indices * sizeof(IndexType),
             VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT |
                 VK_BUFFER_USAGE_TRANSFER_DST_BIT,
             static_cast<VkMemoryPropertyFlagBits>(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT), device,
             physical_device
         ),
         vertex_data_size_(vertex_data_size),
         num_indices_(num_indices) {}

   inline IndexType num_indices() const {
      return num_indices_;
   }

   inline VkDeviceSize index_offset() const {
      return vertex_data_size_;
   }

private:
   size_t vertex_data_size_;
   IndexType num_indices_;
};

class StagingBuffer : public Buffer {
public:
   explicit StagingBuffer(
       VkDeviceSize capacity, VkDevice device, const PhysicalDevice &physical_device
   );

   inline void upload_raw(void *data, size_t size) const {
      std::memcpy(mem_map_, data, size);
   }

   void upload_mesh(
       const std::span<uint8_t> vertex_data,
       const std::span<VertexIndexBuffer::IndexType> index_data
   );

   inline VkDeviceSize capacity() const {
      return capacity_;
   }

   inline VkDeviceSize size() const {
      return size_;
   }

private:
   VkDeviceSize capacity_;
   VkDeviceSize size_;
   void *mem_map_;
};

class UniformBuffer : public Buffer {
public:
   explicit UniformBuffer(
       VkDeviceSize element_size, VkDeviceSize num_elements, VkDevice device,
       const PhysicalDevice &physical_device
   );

   UniformBuffer(UniformBuffer &&other);

   inline ~UniformBuffer() {
      bool buffer_was_moved = allocation_ == nullptr;
      if (!buffer_was_moved) {
         vkUnmapMemory(device_, allocation_);
      }
   }

   inline void upload_memory(void *data, size_t size, size_t element_index) {
      uint8_t *start = reinterpret_cast<uint8_t *>(mem_map_) + element_index * element_size_;
      std::memcpy(start, data, size);
   }

   inline VkDeviceSize element_size() const {
      return element_size_;
   }

private:
   VkDeviceSize element_size_;
   void *mem_map_;
};

} // namespace vkad

#endif // !VKAD_GPU_BUFFER_H_
