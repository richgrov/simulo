#ifndef VILLA_GPU_BUFFER_H_
#define VILLA_GPU_BUFFER_H_

#include "vulkan/vulkan_core.h"
#include <cstring>

namespace villa {

class Buffer {
public:
   explicit Buffer(
       size_t size, VkBufferUsageFlags usage, VkMemoryPropertyFlagBits memory_properties,
       VkDevice device, VkPhysicalDevice physical_device
   );

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

class VertexBuffer : public Buffer {
public:
   explicit inline VertexBuffer(
       size_t num_vertices, size_t vertex_size, VkDevice device, VkPhysicalDevice physical_device
   )
       : Buffer(
             num_vertices * vertex_size,
             VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
             static_cast<VkMemoryPropertyFlagBits>(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT), device,
             physical_device
         ),
         num_vertices_(num_vertices) {}

   inline size_t num_vertices() const {
      return num_vertices_;
   }

private:
   size_t num_vertices_;
};

class IndexBuffer : public Buffer {
public:
   using IndexType = uint16_t;

   explicit inline IndexBuffer(
       IndexType num_indices, VkDevice device, VkPhysicalDevice physical_device
   )
       : Buffer(
             sizeof(IndexType) * num_indices,
             VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
             static_cast<VkMemoryPropertyFlagBits>(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT), device,
             physical_device
         ),
         num_indices_(num_indices) {}

   inline IndexType num_indices() const {
      return num_indices_;
   }

private:
   IndexType num_indices_;
};

class StagingBuffer : public Buffer {
public:
   StagingBuffer(VkDeviceSize capacity, VkDevice device, VkPhysicalDevice physical_device)
       : Buffer(
             capacity, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
             static_cast<VkMemoryPropertyFlagBits>(
                 VK_MEMORY_PROPERTY_HOST_COHERENT_BIT | VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
             ),
             device, physical_device
         ),
         capacity_(capacity), size_(0) {}

   void upload_memory(void *data, size_t size);

   inline VkDeviceSize capacity() const {
      return capacity_;
   }

   inline VkDeviceSize size() const {
      return size_;
   }

private:
   VkDeviceSize capacity_;
   VkDeviceSize size_;
};

class UniformBuffer : public Buffer {
public:
   explicit UniformBuffer(VkDeviceSize capacity, VkDevice device, VkPhysicalDevice physical_device);

   inline ~UniformBuffer() {
      vkUnmapMemory(device_, allocation_);
   }

   inline void upload_memory(void *data, size_t size) {
      std::memcpy(mem_map_, data, size);
   }

private:
   void *mem_map_;
};

} // namespace villa

#endif // !VILLA_GPU_BUFFER_H_
