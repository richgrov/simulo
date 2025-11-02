#pragma once

#include <vulkan/vulkan.h>

namespace simulo {

constexpr const char *kValidationLayers[] = {
    "VK_LAYER_KHRONOS_validation",
    //"VK_LAYER_LUNARG_api_dump",
};

#ifdef __cplusplus
extern "C" {
#endif
struct GpuWrapper {
   VkInstance instance_;
   VkPhysicalDevice physical_device_;
   VkDeviceSize min_uniform_alignment_;
   VkPhysicalDeviceMemoryProperties mem_properties_;
   uint32_t graphics_queue_;
   uint32_t present_queue_;
};
#ifdef __cplusplus
}
#endif

class Gpu {
public:
   Gpu(GpuWrapper properties);

   // inline ~Gpu() {
   //    vkDestroyInstance(wrapper_.instance_, nullptr);
   // }

   Gpu(const Gpu &other) = delete;
   Gpu &operator=(const Gpu &other) = delete;

   inline VkInstance instance() const {
      return wrapper_.instance_;
   }

   inline VkPhysicalDevice physical_device() const {
      return wrapper_.physical_device_;
   }

   inline VkDeviceSize min_uniform_alignment() const {
      return wrapper_.min_uniform_alignment_;
   }

   inline VkPhysicalDeviceMemoryProperties mem_properties() const {
      return wrapper_.mem_properties_;
   }

   bool initialize_surface(VkSurfaceKHR surface);

   inline uint32_t graphics_queue() const {
      return wrapper_.graphics_queue_;
   }

   inline uint32_t present_queue() const {
      return wrapper_.present_queue_;
   }

   uint32_t find_memory_type_index(uint32_t supported_bits, VkMemoryPropertyFlagBits extra) const;

private:
   bool find_queue_families(VkPhysicalDevice candidate_device, VkSurfaceKHR surface);

   GpuWrapper wrapper_;
};

} // namespace simulo
