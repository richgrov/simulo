#include "physical_device.h"

#include <stdexcept>
#include <vector>
#include <vulkan/vulkan_core.h>

#include "gpu/instance.h"
#include "gpu/swapchain.h"

using namespace villa;

PhysicalDevice::PhysicalDevice(const Instance &instance, VkSurfaceKHR surface) {
   uint32_t num_devices;
   vkEnumeratePhysicalDevices(instance.handle(), &num_devices, nullptr);
   if (num_devices == 0) {
      throw std::runtime_error("no physical devices");
   }

   std::vector<VkPhysicalDevice> devices(num_devices);
   vkEnumeratePhysicalDevices(instance.handle(), &num_devices, devices.data());

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
      if (!graphics_found && (queue_families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) == 1) {
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
