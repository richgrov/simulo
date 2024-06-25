#include "gpu.h"

#include <stdexcept>
#include <vector>

#include <vulkan/vulkan_core.h>

using namespace villa;

namespace {

#ifdef VILLA_DEBUG
bool validation_layers_supported(const std::vector<const char *> layers) {
   uint32_t total_layers;
   vkEnumerateInstanceLayerProperties(&total_layers, nullptr);

   std::vector<VkLayerProperties> all_layers(total_layers);
   vkEnumerateInstanceLayerProperties(&total_layers, all_layers.data());

   for (const char *const layer_name : layers) {
      bool match = false;

      for (const auto &layer : all_layers) {
         if (strcmp(layer_name, layer.layerName) == 0) {
            match = true;
            break;
         }
      }

      if (!match) {
         return false;
      }
   }

   return true;
}
#endif

} // namespace

Gpu::Gpu() {
   VkApplicationInfo app_info = {
       .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
       .pApplicationName = "villa",
       .applicationVersion = VK_MAKE_VERSION(1, 0, 0),
       .pEngineName = "villa",
       .engineVersion = VK_MAKE_VERSION(1, 0, 0),
       .apiVersion = VK_API_VERSION_1_0,
   };

   VkInstanceCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
       .pApplicationInfo = &app_info,
   };
   // TODO extensions?

#ifdef VILLA_DEBUG
   std::vector<const char *> validation_layers = {"VK_LAYER_KHRONOS_validation"};
   if (!validation_layers_supported(validation_layers)) {
      throw std::runtime_error("validation layers not supported");
   }

   create_info.enabledLayerCount = static_cast<uint32_t>(validation_layers.size());
   create_info.ppEnabledLayerNames = validation_layers.data();
#endif

   if (vkCreateInstance(&create_info, nullptr, &vk_instance_) != VK_SUCCESS) {
      throw std::runtime_error("failed to create vulkan instance");
   }
}

Gpu::~Gpu() {
   vkDestroyInstance(vk_instance_, nullptr);
}
