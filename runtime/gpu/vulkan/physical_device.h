#pragma once

#include "gpu.h"
#include <vulkan/vulkan_core.h>

namespace simulo {

class PhysicalDevice {
public:
   PhysicalDevice(const Gpu &instance, VkSurfaceKHR surface);

   PhysicalDevice(const PhysicalDevice &other) = delete;
   PhysicalDevice &operator=(const PhysicalDevice &other) = delete;

   inline VkPhysicalDevice handle() const {
      return physical_device_;
   }

   inline VkDeviceSize min_uniform_alignment() const {
      return min_uniform_alignment_;
   }

   inline uint32_t graphics_queue() const {
      return graphics_queue_;
   }

   inline uint32_t present_queue() const {
      return present_queue_;
   }

   uint32_t find_memory_type_index(uint32_t supported_bits, VkMemoryPropertyFlagBits extra) const;

   bool supports_srgb_texture_format(VkFormat format) const;

private:
   bool find_queue_families(VkPhysicalDevice candidate_device, VkSurfaceKHR surface);

   VkPhysicalDevice physical_device_;
   VkPhysicalDeviceMemoryProperties mem_properties_;
   VkDeviceSize min_uniform_alignment_;
   uint32_t graphics_queue_;
   uint32_t present_queue_;
};

} // namespace simulo
