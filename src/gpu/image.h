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

private:
   VkImage image_;
   VkDeviceMemory allocation_;
   VkDevice device_;
};

} // namespace villa

#endif // !VILLA_GPU_IMAGE_H_
