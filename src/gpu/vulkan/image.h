#ifndef VKAD_GPU_VULKAN_IMAGE_H_
#define VKAD_GPU_VULKAN_IMAGE_H_

#include "physical_device.h"
#include <vulkan/vulkan_core.h>

namespace vkad {

class Image {
public:
   Image(
       const PhysicalDevice &physical_device, VkDevice device, VkImageUsageFlags usage,
       VkFormat format, uint32_t width, uint32_t height
   );

   ~Image();

   void init_view();

   void queue_transfer_layout(VkImageLayout layout, VkCommandBuffer cmd_buf);

   inline VkImage handle() const {
      return image_;
   }

   inline VkImageView view() const {
      return view_;
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
   VkImageView view_;
   VkFormat format_;
   VkDeviceMemory allocation_;
   uint32_t width_;
   uint32_t height_;
   VkDevice device_;
   VkImageLayout layout_;
};

} // namespace vkad

#endif // !VKAD_GPU_VULKAN_IMAGE_H_
