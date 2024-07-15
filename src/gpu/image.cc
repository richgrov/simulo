#include "image.h"

#include <vulkan/vulkan_core.h>

#define STB_IMAGE_IMPLEMENTATION
#include "vendor/stb_image.h"

#include "status.h"

using namespace vkad;

Image::Image(
    const PhysicalDevice &physical_device, VkDevice device, VkImageUsageFlags usage,
    VkFormat format, uint32_t width, uint32_t height
)
    : view_(VK_NULL_HANDLE), format_(format), device_(device), layout_(VK_IMAGE_LAYOUT_UNDEFINED),
      width_(width), height_(height) {
   VkImageCreateInfo image_create = {
       .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
       .imageType = VK_IMAGE_TYPE_2D,
       .format = format,
       .extent = {width, height, 1},
       .mipLevels = 1,
       .arrayLayers = 1,
       .samples = VK_SAMPLE_COUNT_1_BIT,
       .tiling = VK_IMAGE_TILING_OPTIMAL,
       .usage = usage,
       .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
       .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
   };
   VKAD_VK(vkCreateImage(device, &image_create, nullptr, &image_));

   VkMemoryRequirements img_mem;
   vkGetImageMemoryRequirements(device, image_, &img_mem);

   VkMemoryAllocateInfo alloc = {
       .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
       .allocationSize = img_mem.size,
       .memoryTypeIndex = physical_device.find_memory_type_index(
           img_mem.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
       ),
   };

   VKAD_VK(vkAllocateMemory(device, &alloc, nullptr, &allocation_));
   VKAD_VK(vkBindImageMemory(device, image_, allocation_, 0));
}

Image::~Image() {
   if (view_ != VK_NULL_HANDLE) {
      vkDestroyImageView(device_, view_, nullptr);
   }

   vkDestroyImage(device_, image_, nullptr);
   vkFreeMemory(device_, allocation_, nullptr);
}

void Image::init_view() {
   VkImageViewCreateInfo view_create = {
       .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
       .image = image_,
       .viewType = VK_IMAGE_VIEW_TYPE_2D,
       .format = format_,
       .subresourceRange =
           {
               .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
               .baseMipLevel = 0,
               .levelCount = 1,
               .baseArrayLayer = 0,
               .layerCount = 1,
           },
   };
   VKAD_VK(vkCreateImageView(device_, &view_create, nullptr, &view_));
}

void Image::queue_transfer_layout(VkImageLayout layout, VkCommandBuffer cmd_buf) {
   VkImageMemoryBarrier barrier = {
       .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
       .oldLayout = layout_,
       .newLayout = layout,
       .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
       .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
       .image = image_,
       .subresourceRange =
           {
               .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
               .baseMipLevel = 0,
               .levelCount = 1,
               .baseArrayLayer = 0,
               .layerCount = 1,
           },
   };

   VkPipelineStageFlags src_stage = 0;
   VkPipelineStageFlags dst_stage = 0;
   switch (layout_) {
   case VK_IMAGE_LAYOUT_UNDEFINED:
      src_stage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
      break;

   case VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL:
      barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
      src_stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
      break;

   default:
      break;
   }

   switch (layout) {
   case VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL:
      barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
      dst_stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
      break;

   case VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL:
      barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
      dst_stage = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
      break;

   default:
      break;
   }

   layout_ = layout;
   vkCmdPipelineBarrier(cmd_buf, src_stage, dst_stage, 0, 0, nullptr, 0, nullptr, 1, &barrier);
}
