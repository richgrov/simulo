#ifndef VILLA_GPU_BUFFER_H_
#define VILLA_GPU_BUFFER_H_

#include "vulkan/vulkan_core.h"
namespace villa {

class Buffer {
public:
   explicit Buffer(
       size_t size, VkBufferUsageFlags usage, VkDevice device, VkPhysicalDevice physical_device
   );

   inline ~Buffer() {
      vkDestroyBuffer(device_, buffer_, nullptr);
      vkFreeMemory(device_, allocation_, nullptr);
   }

   void upload_memory(void *data, size_t size);

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
             num_vertices * vertex_size, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, device, physical_device
         ),
         num_vertices_(num_vertices) {}

   inline size_t num_vertices() const {
      return num_vertices_;
   }

private:
   size_t num_vertices_;
};

} // namespace villa

#endif // !VILLA_GPU_BUFFER_H_
