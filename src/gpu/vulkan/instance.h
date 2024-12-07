#ifndef VKAD_GPU_VULKAN_INSTANCE_H_
#define VKAD_GPU_VULKAN_INSTANCE_H_

#include <vector>
#include <vulkan/vulkan_core.h>

namespace vkad {

constexpr const char *kValidationLayers[] = {
    "VK_LAYER_KHRONOS_validation",
    //"VK_LAYER_LUNARG_api_dump",
};

class Instance {
public:
   Instance(const std::vector<const char *> extensions);

   inline ~Instance() {
      vkDestroyInstance(instance_, nullptr);
   }

   Instance(const Instance &other) = delete;
   Instance &operator=(const Instance &other) = delete;

   inline VkInstance handle() const {
      return instance_;
   }

private:
   VkInstance instance_;
};

} // namespace vkad

#endif // !VKAD_GPU_VULKAN_INSTANCE_H_
