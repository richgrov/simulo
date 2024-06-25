#ifndef VILLA_GPU_VK_GPU_H_
#define VILLA_GPU_VK_GPU_H_

#include <vulkan/vulkan_core.h>

namespace villa {

class Gpu {
public:
   explicit Gpu();

private:
   VkInstance vk_instance_;
};

}; // namespace villa

#endif // !VILLA_GPU_VK_GPU_H_
