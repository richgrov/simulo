#include "physical_device.h"

#include <format>
#include <stdexcept>
#include <vector>
#include <vulkan/vulkan_core.h>

#include "gpu.h"
#include "status.h"
#include "swapchain.h"

using namespace simulo;

PhysicalDevice::PhysicalDevice(const Gpu &instance, VkSurfaceKHR surface) {
   uint32_t num_devices;
   VKAD_VK(vkEnumeratePhysicalDevices(instance.instance(), &num_devices, nullptr));
   if (num_devices == 0) {
      throw std::runtime_error("no physical devices");
   }

   std::vector<VkPhysicalDevice> devices(num_devices);
   vkEnumeratePhysicalDevices(instance.instance(), &num_devices, devices.data());

   for (const auto &device : devices) {
      if (!Swapchain::is_supported_on(device, surface)) {
         continue;
      }

      if (!find_queue_families(device, surface)) {
         continue;
      }

      physical_device_ = device;

      VkPhysicalDeviceProperties properties;
      vkGetPhysicalDeviceProperties(physical_device_, &properties);
      min_uniform_alignment_ = properties.limits.minUniformBufferOffsetAlignment;

      vkGetPhysicalDeviceMemoryProperties(device, &mem_properties_);
      return;
   }

   throw std::runtime_error("no suitable physical device");
}

bool PhysicalDevice::find_queue_families(VkPhysicalDevice candidate_device, VkSurfaceKHR surface) {
   uint32_t num_queue_families;
   vkGetPhysicalDeviceQueueFamilyProperties(candidate_device, &num_queue_families, nullptr);

   std::vector<VkQueueFamilyProperties> queue_families(num_queue_families);
   vkGetPhysicalDeviceQueueFamilyProperties(
       candidate_device, &num_queue_families, queue_families.data()
   );

   bool graphics_found = false;
   bool presentation_found = false;
   for (int i = 0; i < queue_families.size(); ++i) {
      if (!graphics_found && (queue_families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0) {
         graphics_queue_ = i;
         graphics_found = true;
      }

      if (!presentation_found) {
         VkBool32 supported = false;
         vkGetPhysicalDeviceSurfaceSupportKHR(candidate_device, i, surface, &supported);
         if (supported) {
            present_queue_ = i;
            presentation_found = true;
         }
      }
   }

   return graphics_found && presentation_found;
}

uint32_t PhysicalDevice::find_memory_type_index(
    uint32_t supported_bits, VkMemoryPropertyFlagBits extra
) const {
   VkMemoryType mem_type;
   for (int i = 0; i < mem_properties_.memoryTypeCount; ++i) {
      bool supports_mem_type = (supported_bits & (1 << i)) != 0;
      bool supports_extra = (mem_properties_.memoryTypes[i].propertyFlags & extra) == extra;
      if (supports_mem_type && supports_extra) {
         return i;
      }
   }

   throw std::runtime_error(std::format(
       "no suitable memory type for bits {} and extra flags {}", supported_bits, (int)extra
   ));
}

bool PhysicalDevice::supports_srgb_texture_format(VkFormat format) const {
   VkFormatProperties properties;
   vkGetPhysicalDeviceFormatProperties(physical_device_, format, &properties);
   
   // Check if the format supports being used as a sampled image (texture)
   return (properties.optimalTilingFeatures & VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT) != 0;
}