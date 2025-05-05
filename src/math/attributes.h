#pragma once

#include <cstddef>

#include <vulkan/vulkan_core.h>

namespace simulo {

#define VKAD_ATTRIBUTE(index, type, member)                                                        \
   VkVertexInputAttributeDescription {                                                             \
      .location = index, .binding = 0, .format = decltype(type::member)::format(),                 \
      .offset = offsetof(type, member),                                                            \
   }

} // namespace simulo
