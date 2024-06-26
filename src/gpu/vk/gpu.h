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

private:
   VkInstance vk_instance_;
   VkDevice device_;
};

}; // namespace villa

#endif // !VILLA_GPU_VK_GPU_H_
