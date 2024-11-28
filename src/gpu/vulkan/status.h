#ifndef VKAD_GPU_VULKAN_STATUS_H_
#define VKAD_GPU_VULKAN_STATUS_H_

#include <format>
#include <stdexcept>
#include <vulkan/vk_enum_string_helper.h>

#define VKAD_VK(x)                                                                                 \
   {                                                                                               \
      VkResult result__ = (x);                                                                     \
      if (result__ != VK_SUCCESS) {                                                                \
         throw std::runtime_error(                                                                 \
             std::format("Error {} at {}:{}", string_VkResult(result__), __FILE__, __LINE__)       \
         );                                                                                        \
      }                                                                                            \
   }

#endif // !VKAD_GPU_VULKAN_STATUS_H_
