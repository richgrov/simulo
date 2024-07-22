#ifndef VKAD_MATH_SIZES_H_
#define VKAD_MATH_SIZES_H_

#include <cstddef>

#include <vulkan/vulkan_core.h>

namespace vkad {

#define VKAD_ATTRIBUTE(index, type, member)                                                        \
   VkVertexInputAttributeDescription {                                                             \
      .location = index, .binding = 0, .format = decltype(type::member)::kFormat,                  \
      .offset = offsetof(type, member),                                                            \
   }

} // namespace vkad

#endif // !VKAD_MATH_SIZES_H_
