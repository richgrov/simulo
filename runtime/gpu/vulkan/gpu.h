#pragma once

#include <vulkan/vulkan_core.h>

namespace simulo {

constexpr const char *kValidationLayers[] = {
    "VK_LAYER_KHRONOS_validation",
    //"VK_LAYER_LUNARG_api_dump",
};

class Gpu {
public:
   Gpu();

   inline ~Gpu() {
      vkDestroyInstance(instance_, nullptr);
   }

   Gpu(const Gpu &other) = delete;
   Gpu &operator=(const Gpu &other) = delete;

   inline VkInstance instance() const {
      return instance_;
   }

   inline VkPhysicalDevice physical_device() const {
      return physical_device_;
   }

   inline VkDeviceSize min_uniform_alignment() const {
      return min_uniform_alignment_;
   }

   inline VkPhysicalDeviceMemoryProperties mem_properties() const {
      return mem_properties_;
   }

   bool initialize_surface(VkSurfaceKHR surface);

   inline uint32_t graphics_queue() const {
      return graphics_queue_;
   }

   inline uint32_t present_queue() const {
      return present_queue_;
   }

   uint32_t find_memory_type_index(uint32_t supported_bits, VkMemoryPropertyFlagBits extra) const;

private:
   bool find_queue_families(VkPhysicalDevice candidate_device, VkSurfaceKHR surface);

   VkInstance instance_;
   VkPhysicalDevice physical_device_;
   VkDeviceSize min_uniform_alignment_;
   VkPhysicalDeviceMemoryProperties mem_properties_;
   uint32_t graphics_queue_;
   uint32_t present_queue_;
};

} // namespace simulo
