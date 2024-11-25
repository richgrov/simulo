#include "instance.h"

#include <cstring>
#include <format>
#include <iostream>
#include <stdexcept>
#include <vector>

#include "status.h"
#include "util/memory.h"

using namespace vkad;

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

Instance::Instance(const std::vector<const char *> extensions) {
   VkApplicationInfo app_info = {
       .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
       .applicationVersion = VK_MAKE_VERSION(1, 0, 0),
       .engineVersion = VK_MAKE_VERSION(1, 0, 0),
       .apiVersion = VK_API_VERSION_1_0,
   };

   VkInstanceCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
       .pApplicationInfo = &app_info,
       .enabledExtensionCount = static_cast<uint32_t>(extensions.size()),
       .ppEnabledExtensionNames = extensions.data(),
   };

#ifdef VKAD_DEBUG
   ensure_validation_layers_supported();
   create_info.enabledLayerCount = VKAD_ARRAY_LEN(kValidationLayers);
   create_info.ppEnabledLayerNames = kValidationLayers;
   std::cout << "Validation layers enabled\n";
#endif

   VKAD_VK(vkCreateInstance(&create_info, nullptr, &instance_));
}
