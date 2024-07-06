#ifndef VILLA_GPU_PHYSICAL_DEVICE_H_
#define VILLA_GPU_PHYSICAL_DEVICE_H_

#include "gpu/instance.h"
#include <vulkan/vulkan_core.h>

namespace villa {

class PhysicalDevice {
public:
   PhysicalDevice(const Instance &instance, VkSurfaceKHR surface);

   inline VkPhysicalDevice handle() const {
      return physical_device_;
   }

   inline uint32_t min_uniform_alignment() const {
      return min_uniform_alignment_;
   }

   inline uint32_t graphics_queue() const {
      return graphics_queue_;
   }

   inline uint32_t present_queue() const {
      return graphics_queue_;
   }

private:
   bool find_queue_families(VkPhysicalDevice candidate_device, VkSurfaceKHR surface);

   VkPhysicalDevice physical_device_;
   VkDeviceSize min_uniform_alignment_;
   uint32_t graphics_queue_;
   uint32_t present_queue_;
};

} // namespace villa

#endif // !VILLA_GPU_PHYSICAL_DEVICE_H_
