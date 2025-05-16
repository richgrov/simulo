#pragma once

#include <vulkan/vulkan_core.h>

namespace simulo {

constexpr const char *kValidationLayers[] = {
    "VK_LAYER_KHRONOS_validation",
    //"VK_LAYER_LUNARG_api_dump",
};

class Gpu {
public:
   Gpu();

   inline ~Gpu() {
      vkDestroyInstance(instance_, nullptr);
   }

   Gpu(const Gpu &other) = delete;
   Gpu &operator=(const Gpu &other) = delete;

   inline VkInstance instance() const {
      return instance_;
   }

private:
   VkInstance instance_;
};

} // namespace simulo
