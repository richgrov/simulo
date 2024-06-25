#include "gpu.h"

#include <stdexcept>
#include <vulkan/vulkan_core.h>

using namespace villa;

Gpu::Gpu() {
   VkApplicationInfo app_info = {};
   app_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
   app_info.pApplicationName = "villa";
   app_info.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
   app_info.pEngineName = "villa";
   app_info.engineVersion = VK_MAKE_VERSION(1, 0, 0);
   app_info.apiVersion = VK_API_VERSION_1_0;

   VkInstanceCreateInfo create_info = {};
   create_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
   create_info.pApplicationInfo = &app_info;
   // TODO extensions?
   create_info.enabledLayerCount = 0;

   if (vkCreateInstance(&create_info, nullptr, &vk_instance_) != VK_SUCCESS) {
      throw std::runtime_error("failed to create vulkan instance");
   }
}

Gpu::~Gpu() {
   vkDestroyInstance(vk_instance_, nullptr);
}
