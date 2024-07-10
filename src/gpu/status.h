#ifndef VILLA_GPU_STATUS_H_
#define VILLA_GPU_STATUS_H_

#include <format>
#include <stdexcept>
#include <vulkan/vk_enum_string_helper.h>

#define VILLA_VK(x)                                                                                \
   {                                                                                               \
      VkResult result = (x);                                                                       \
      if (result != VK_SUCCESS) {                                                                  \
         throw std::runtime_error(                                                                 \
             std::format("Error {} at {}:{}", string_VkResult(result), __FILE__, __LINE__)         \
         );                                                                                        \
      }                                                                                            \
   }

#endif // !VILLA_GPU_STATUS_H_
