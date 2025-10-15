#pragma once

#include <vulkan/vulkan_core.h>

#include "gpu.h"

namespace simulo {

class Device {
public:
   Device(const Gpu &gpu);
   ~Device();

   Device(const Device &other) = delete;
   Device &operator=(const Device &other) = delete;

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

} // namespace simulo
