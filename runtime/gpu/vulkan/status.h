#pragma once

#include <format>
#include <stdexcept>
// #include <vulkan/vk_enum_string_helper.h>

#define VKAD_VK(x)                                                                                 \
   {                                                                                               \
      VkResult result__ = (x);                                                                     \
      if (result__ != VK_SUCCESS) {                                                                \
         throw std::runtime_error(std::format("Error {} at {}:{}", "<temp>", __FILE__, __LINE__)); \
      }                                                                                            \
   }
