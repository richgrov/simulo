#include "image.h"

#include <stdexcept>

#include <vulkan/vulkan_core.h>

#define STB_IMAGE_IMPLEMENTATION
#include "vendor/stb_image.h"

using namespace villa;

Image::Image(
    const PhysicalDevice &physical_device, VkDevice device, VkImageUsageFlags usage, uint32_t width,
    uint32_t height
)
    : device_(device), layout_(VK_IMAGE_LAYOUT_UNDEFINED), width_(width), height_(height) {
   VkImageCreateInfo image_create = {
       .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
       .imageType = VK_IMAGE_TYPE_2D,
       .format = VK_FORMAT_R8G8B8A8_UNORM,
       .extent = {width, height, 1},
       .mipLevels = 1,
       .arrayLayers = 1,
       .samples = VK_SAMPLE_COUNT_1_BIT,
       .tiling = VK_IMAGE_TILING_OPTIMAL,
       .usage = usage,
       .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
       .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
   };

   if (vkCreateImage(device, &image_create, nullptr, &image_) != VK_SUCCESS) {
      throw std::runtime_error("failed to create path tracing image");
   }

   VkMemoryRequirements img_mem;
   vkGetImageMemoryRequirements(device, image_, &img_mem);

   VkMemoryAllocateInfo alloc = {
       .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
       .allocationSize = img_mem.size,
       .memoryTypeIndex = physical_device.find_memory_type_index(
           img_mem.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
       ),
   };

   if (vkAllocateMemory(device, &alloc, nullptr, &allocation_) != VK_SUCCESS) {
      throw std::runtime_error("failed to allocate image memory");
   }

   if (vkBindImageMemory(device, image_, allocation_, 0) != VK_SUCCESS) {
      throw std::runtime_error("failed to bind image memory");
   }
}

Image::~Image() {
   vkDestroyImage(device_, image_, nullptr);
   vkFreeMemory(device_, allocation_, nullptr);
}
