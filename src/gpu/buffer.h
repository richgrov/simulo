#ifndef VILLA_GPU_BUFFER_H_
#define VILLA_GPU_BUFFER_H_

#include "vulkan/vulkan_core.h"

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

   virtual void upload_memory(void *data, size_t size);

   inline VkBuffer buffer() const {
      return buffer_;
   }

private:
   VkBuffer buffer_;
   VkDeviceMemory allocation_;
   VkDevice device_;
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

   virtual void upload_memory(void *data, size_t size) override;

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

} // namespace villa

#endif // !VILLA_GPU_BUFFER_H_
