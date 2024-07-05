#ifndef VILLA_GPU_INSTANCE_H_
#define VILLA_GPU_INSTANCE_H_

#include <vector>
#include <vulkan/vulkan_core.h>

namespace villa {

constexpr const char *validation_layers[] = {"VK_LAYER_KHRONOS_validation"};

class Instance {
public:
   Instance(const std::vector<const char *> extensions);

   inline ~Instance() {
      vkDestroyInstance(instance_, nullptr);
   }

   inline VkInstance handle() const {
      return instance_;
   }

private:
   VkInstance instance_;
};

} // namespace villa

#endif // !VILLA_GPU_INSTANCE_H_
