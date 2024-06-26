#ifndef VILLA_GPU_VK_GPU_H_
#define VILLA_GPU_VK_GPU_H_

#include <vector>

#include <vulkan/vulkan_core.h>

namespace villa {

class Gpu {
public:
   explicit Gpu();
   ~Gpu();

   void init(const std::vector<const char *> &extensions);

   inline VkInstance instance() const {
      return vk_instance_;
   }

   inline void set_surface(VkSurfaceKHR surface) {
      surface_ = surface;
   }

private:
   VkInstance vk_instance_;
   VkDevice device_;
   VkSurfaceKHR surface_;
};

}; // namespace villa

#endif // !VILLA_GPU_VK_GPU_H_
