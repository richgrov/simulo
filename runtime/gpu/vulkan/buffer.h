#pragma once

#include <cstring>
#include <span>

#include <vulkan/vulkan_core.h>

#include "ffi.h"
#include "physical_device.h"

namespace simulo {

void buffer_init(
    VkBuffer *buffer, VkDeviceMemory *allocation, size_t size, VkBufferUsageFlags usage,
    VkMemoryPropertyFlagBits memory_properties, VkDevice device,
    const PhysicalDevice &physical_device
);
void buffer_destroy(VkBuffer *buffer, VkDeviceMemory *allocation, VkDevice device);

class StagingBuffer {
public:
   explicit StagingBuffer(
       VkDeviceSize capacity, VkDevice device, const PhysicalDevice &physical_device
   );

   StagingBuffer(const StagingBuffer &) = delete;
   StagingBuffer &operator=(const StagingBuffer &) = delete;

   StagingBuffer(StagingBuffer &&other);

   StagingBuffer &operator=(StagingBuffer &&other);

   inline void upload_raw(void *data, size_t size) const {
      std::memcpy(mem_map_, data, size);
   }

   void
   upload_mesh(const std::span<uint8_t> vertex_data, const std::span<IndexBufferType> index_data);

   inline VkDeviceSize capacity() const {
      return capacity_;
   }

   inline VkDeviceSize size() const {
      return size_;
   }

   inline VkBuffer buffer() const {
      return buffer_;
   }

private:
   VkDevice device_;
   VkBuffer buffer_;
   VkDeviceMemory allocation_;
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

   UniformBuffer(const UniformBuffer &) = delete;
   UniformBuffer &operator=(const UniformBuffer &) = delete;

   UniformBuffer(UniformBuffer &&other);
   UniformBuffer &operator=(UniformBuffer &&other);

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

   inline VkBuffer buffer() const {
      return buffer_;
   }

private:
   VkDevice device_;
   VkBuffer buffer_;
   VkDeviceMemory allocation_;
   VkDeviceSize element_size_;
   void *mem_map_;
};

} // namespace simulo
