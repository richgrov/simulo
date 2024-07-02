#include "swapchain.h"

#include <algorithm>
#include <cstring>
#include <optional>
#include <stdexcept>

#include <vulkan/vulkan_core.h>

using namespace villa;

bool has_swapchain_support(VkPhysicalDevice device) {
   uint32_t num_extensions;
   vkEnumerateDeviceExtensionProperties(device, nullptr, &num_extensions, nullptr);

   std::vector<VkExtensionProperties> extensions(num_extensions);
   vkEnumerateDeviceExtensionProperties(device, nullptr, &num_extensions, extensions.data());

   for (const auto &ext : extensions) {
      if (strcmp(ext.extensionName, VK_KHR_SWAPCHAIN_EXTENSION_NAME) == 0) {
         return true;
      }
   }
   return false;
}

std::optional<SwapchainCreationInfo>
Swapchain::get_creation_info(VkPhysicalDevice device, VkSurfaceKHR surface) {
   if (!has_swapchain_support(device)) {
      return std::nullopt;
   }

   uint32_t num_formats;
   vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &num_formats, nullptr);
   uint32_t num_present_modes;
   vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &num_present_modes, nullptr);

   if (num_formats < 1 || num_present_modes < 1) {
      return std::nullopt;
   }

   std::vector<VkSurfaceFormatKHR> formats(num_formats);
   vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &num_formats, formats.data());

   std::vector<VkPresentModeKHR> present_modes(num_present_modes);
   vkGetPhysicalDeviceSurfacePresentModesKHR(
       device, surface, &num_present_modes, present_modes.data()
   );

   VkSurfaceCapabilitiesKHR capabilities;
   if (vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &capabilities) != VK_SUCCESS) {
      throw std::runtime_error("couldn't get surface capabilities");
   }

   return std::make_optional(SwapchainCreationInfo{
       .surface_formats = std::move(formats),
       .present_modes = std::move(present_modes),
       .surface_capabilities = std::move(capabilities),
   });
}

VkSurfaceFormatKHR best_surface_format(const std::vector<VkSurfaceFormatKHR> &formats) {
   for (const auto fmt : formats) {
      if (fmt.format == VK_FORMAT_R8G8B8A8_SRGB &&
          fmt.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
         return fmt;
      }
   }

   return formats.at(0);
}

VkPresentModeKHR best_present_mode(const std::vector<VkPresentModeKHR> &present_modes) {
   for (const auto mode : present_modes) {
      if (mode == VK_PRESENT_MODE_MAILBOX_KHR) {
         return mode;
      }
   }

   return VK_PRESENT_MODE_FIFO_KHR;
}

VkExtent2D
create_swap_extent(const VkSurfaceCapabilitiesKHR &capa, uint32_t width, uint32_t height) {
   VkExtent2D result = capa.currentExtent;

   if (capa.currentExtent.width == static_cast<uint32_t>(-1)) {
      result.width = std::clamp(width, capa.minImageExtent.width, capa.maxImageExtent.width);
      result.height = std::clamp(height, capa.minImageExtent.height, capa.maxImageExtent.height);
   }

   return result;
}

Swapchain::Swapchain() : device_(VK_NULL_HANDLE), swapchain_(VK_NULL_HANDLE) {}

void Swapchain::init(
    SwapchainCreationInfo swapchain_info, const std::vector<uint32_t> &queue_families,
    VkPhysicalDevice physical_device, VkDevice device, VkSurfaceKHR surface, uint32_t width,
    uint32_t height
) {
   device_ = device;

   uint32_t image_count = swapchain_info.surface_capabilities.minImageCount + 1;
   if (swapchain_info.surface_capabilities.maxImageCount != 0 &&
       image_count > swapchain_info.surface_capabilities.maxImageCount) {
      image_count = swapchain_info.surface_capabilities.maxImageCount;
   }

   VkSurfaceFormatKHR format = best_surface_format(swapchain_info.surface_formats);
   img_format_ = format.format;

   extent_ = create_swap_extent(swapchain_info.surface_capabilities, width, height);

   VkSwapchainCreateInfoKHR create_info = {
       .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
       .surface = surface,
       .minImageCount = image_count,
       .imageFormat = format.format,
       .imageColorSpace = format.colorSpace,
       .imageExtent = extent_,
       .imageArrayLayers = 1,
       .imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
       .preTransform = swapchain_info.surface_capabilities.currentTransform,
       .compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
       .presentMode = best_present_mode(swapchain_info.present_modes),
       .clipped = VK_TRUE,
   };

   if (queue_families.at(0) != queue_families.at(1)) {
      create_info.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
      create_info.queueFamilyIndexCount = static_cast<uint32_t>(queue_families.size());
      create_info.pQueueFamilyIndices = queue_families.data();
   }

   if (vkCreateSwapchainKHR(device_, &create_info, nullptr, &swapchain_) != VK_SUCCESS) {
      throw std::runtime_error("failed to create swapchain");
   }

   uint32_t num_images;
   vkGetSwapchainImagesKHR(device, swapchain_, &num_images, nullptr);
   images_.resize(num_images);
   vkGetSwapchainImagesKHR(device, swapchain_, &num_images, images_.data());

   image_views_.resize(images_.size());
   for (int i = 0; i < image_views_.size(); ++i) {
      VkImageViewCreateInfo create_info = {
          .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
          .image = images_[i],
          .viewType = VK_IMAGE_VIEW_TYPE_2D,
          .format = img_format_,
          .subresourceRange =
              {
                  .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
                  .levelCount = 1,
                  .layerCount = 1,
              },
      };

      if (vkCreateImageView(device_, &create_info, nullptr, &image_views_[i]) != VK_SUCCESS) {
         throw std::runtime_error("failed to create image view");
      }
   }
}

void Swapchain::deinit() {
   for (const VkImageView img_view : image_views_) {
      vkDestroyImageView(device_, img_view, nullptr);
   }

   if (swapchain_ != VK_NULL_HANDLE) {
      vkDestroySwapchainKHR(device_, swapchain_, nullptr);
   }
}
