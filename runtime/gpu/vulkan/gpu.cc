#include "gpu.h"

#include <cstring>
#include <format>
#include <iostream>
#include <stdexcept>
#include <vector>

#include "status.h"
#include "util/memory.h"
#include "util/os_detect.h"
#ifdef VKAD_LINUX
#include "window/linux/window.h"
#endif

using namespace simulo;

namespace {

#ifdef VKAD_DEBUG

void ensure_validation_layers_supported() {
   uint32_t total_layers;
   vkEnumerateInstanceLayerProperties(&total_layers, nullptr);

   std::vector<VkLayerProperties> all_layers(total_layers);
   vkEnumerateInstanceLayerProperties(&total_layers, all_layers.data());

   for (const char *const layer_name : kValidationLayers) {
      bool match = false;

      for (const auto &layer : all_layers) {
         if (strcmp(layer_name, layer.layerName) == 0) {
            match = true;
            break;
         }
      }

      if (!match) {
         throw std::runtime_error(std::format("validation layer {} not supported", layer_name));
      }
   }
}
#endif

} // namespace

Gpu::Gpu() {
   VkApplicationInfo app_info = {
       .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
       .applicationVersion = VK_MAKE_VERSION(1, 0, 0),
       .engineVersion = VK_MAKE_VERSION(1, 0, 0),
       .apiVersion = VK_API_VERSION_1_0,
   };

   const char *extensions[] = {
       "VK_KHR_surface",
#ifdef VKAD_WINDOWS
       "VK_KHR_win32_surface",
#elif defined(VKAD_LINUX)

#ifdef SIMULO_KIOSK
      "VK_KHR_display",
      "VK_KHR_get_display_properties2",
#else
       Window::running_on_wayland() ? "VK_KHR_wayland_surface" : "VK_KHR_xlib_surface",
#endif

#endif
   };

   VkInstanceCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
       .pApplicationInfo = &app_info,
       .enabledExtensionCount = static_cast<uint32_t>(VKAD_ARRAY_LEN(extensions)),
       .ppEnabledExtensionNames = extensions,
   };

#ifdef VKAD_DEBUG
   ensure_validation_layers_supported();
   create_info.enabledLayerCount = VKAD_ARRAY_LEN(kValidationLayers);
   create_info.ppEnabledLayerNames = kValidationLayers;
   std::cout << "Validation layers enabled\n";
#endif

   VKAD_VK(vkCreateInstance(&create_info, nullptr, &instance_));

   uint32_t num_devices;
   VKAD_VK(vkEnumeratePhysicalDevices(instance_, &num_devices, nullptr));
   if (num_devices == 0) {
      throw std::runtime_error("no physical devices");
   }

   std::vector<VkPhysicalDevice> devices(num_devices);
   vkEnumeratePhysicalDevices(instance_, &num_devices, devices.data());

   for (const auto &device : devices) {
      VkPhysicalDeviceProperties properties;
      vkGetPhysicalDeviceProperties(device, &properties);

      if (properties.deviceType != VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
         continue;
      }

      physical_device_ = device;
      min_uniform_alignment_ = properties.limits.minUniformBufferOffsetAlignment;
      vkGetPhysicalDeviceMemoryProperties(device, &mem_properties_);
      return;
   }

   throw std::runtime_error("no suitable physical device");
}

bool Gpu::initialize_surface(VkSurfaceKHR surface) {
   return Swapchain::is_supported_on(physical_device_, surface) && find_queue_families(physical_device_, surface);
}

bool Gpu::find_queue_families(VkPhysicalDevice candidate_device, VkSurfaceKHR surface) {
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

uint32_t Gpu::find_memory_type_index(
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