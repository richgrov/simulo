#pragma once

#include "gpu.h"
#include <vulkan/vulkan_core.h>

namespace simulo {

class Image {
public:
   Image(
       const Gpu &gpu, VkDevice device, VkImageUsageFlags usage,
       VkFormat format, uint32_t width, uint32_t height
   );

   ~Image();

   Image(const Image &other) = delete;
   Image &operator=(const Image &other) = delete;

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

} // namespace simulo
