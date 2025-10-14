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

#ifdef(SIMULO_KIOSK)
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
}
