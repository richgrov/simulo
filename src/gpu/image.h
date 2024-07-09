#ifndef VILLA_GPU_IMAGE_H_
#define VILLA_GPU_IMAGE_H_

#include "gpu/physical_device.h"
#include <vulkan/vulkan_core.h>

namespace villa {

class Image {
public:
   Image(
       const PhysicalDevice &physical_device, VkDevice device, VkImageUsageFlags usage,
       uint32_t width, uint32_t height
   );

   ~Image();

   void queue_transfer_layout(VkImageLayout layout, VkCommandBuffer cmd_buf);

   inline VkImage handle() const {
      return image_;
   }

   inline VkImageLayout layout() const {
      return layout_;
   }

   inline uint32_t width() const {
      return width_;
   }

   inline uint32_t height() const {
      return height_;
   }

private:
   VkImage image_;
   VkDeviceMemory allocation_;
   uint32_t width_;
   uint32_t height_;
   VkDevice device_;
   VkImageLayout layout_;
};

} // namespace villa

#endif // !VILLA_GPU_IMAGE_H_
