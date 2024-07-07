#ifndef VILLA_GPU_DEVICE_H_
#define VILLA_GPU_DEVICE_H_

#include <vulkan/vulkan_core.h>

#include "gpu/physical_device.h"

namespace villa {

class Device {
public:
   Device(const PhysicalDevice &physical_device);
   ~Device();

   inline VkDevice handle() const {
      return device_;
   }

   inline VkQueue graphics_queue() const {
      return graphics_queue_;
   }

   inline VkQueue present_queue() const {
      return present_queue_;
   }

   inline void wait_idle() const {
      vkDeviceWaitIdle(device_);
   }

private:
   VkDevice device_;
   VkQueue graphics_queue_;
   VkQueue present_queue_;
};

} // namespace villa

#endif // !VILLA_GPU_DEVICE_H_
