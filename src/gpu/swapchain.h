#ifndef VILLA_GPU_SWAPCHAIN_H_
#define VILLA_GPU_SWAPCHAIN_H_

#include <optional>
#include <vector>
#include <vulkan/vulkan_core.h>

namespace villa {

struct SwapchainCreationInfo {
   std::vector<VkSurfaceFormatKHR> surface_formats;
   std::vector<VkPresentModeKHR> present_modes;
   VkSurfaceCapabilitiesKHR surface_capabilities;
};

class Swapchain {
public:
   Swapchain();

   void init(
       SwapchainCreationInfo swapchain_info, const std::vector<uint32_t> &queue_families,
       VkPhysicalDevice physical_device, VkDevice device, VkSurfaceKHR surface, uint32_t width,
       uint32_t height
   );

   void deinit();

   inline VkFormat img_format() const {
      return img_format_;
   }

   static std::optional<SwapchainCreationInfo>
   get_creation_info(VkPhysicalDevice device, VkSurfaceKHR surface);

private:
   VkDevice device_;
   VkSwapchainKHR swapchain_;
   std::vector<VkImage> images_;
   std::vector<VkImageView> image_views_;
   VkFormat img_format_;
   VkExtent2D extent_;
};

} // namespace villa

#endif // !VILLA_GPU_SWAPCHAIN_H_
