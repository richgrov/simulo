#ifndef VKAD_GPU_VULKAN_DEVICE_H_
#define VKAD_GPU_VULKAN_DEVICE_H_

#include <vulkan/vulkan_core.h>

#include "physical_device.h"

namespace vkad {

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

} // namespace vkad

#endif // !VKAD_GPU_VULKAN_DEVICE_H_
