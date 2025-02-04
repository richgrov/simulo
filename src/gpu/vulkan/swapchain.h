#pragma once

#include <vector>
#include <vulkan/vulkan_core.h>

namespace vkad {

class Swapchain {
public:
   Swapchain(
       const std::vector<uint32_t> &queue_families, VkPhysicalDevice physical_device,
       VkDevice device, VkSurfaceKHR surface, uint32_t width, uint32_t height
   );

   Swapchain &operator=(const Swapchain &other) = delete;

   Swapchain &operator=(Swapchain &&other);

   void dispose();

   ~Swapchain() {
      dispose();
   }

   inline VkSwapchainKHR handle() const {
      return swapchain_;
   }

   inline int num_images() const {
      return images_.size();
   }

   inline VkImageView image_view(int index) const {
      return image_views_[index];
   }

   inline VkFormat img_format() const {
      return img_format_;
   }

   inline VkExtent2D extent() const {
      return extent_;
   }

   static bool is_supported_on(VkPhysicalDevice device, VkSurfaceKHR surface);

private:
   VkDevice device_;
   VkSwapchainKHR swapchain_;
   std::vector<VkImage> images_;
   std::vector<VkImageView> image_views_;
   VkFormat img_format_;
   VkExtent2D extent_;
};

} // namespace vkad
