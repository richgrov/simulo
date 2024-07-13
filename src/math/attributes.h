#ifndef VILLA_MATH_SIZES_H_
#define VILLA_MATH_SIZES_H_

#include <vulkan/vulkan_core.h>

struct VertexAttribute {
   uint32_t size;
   VkFormat format;

   static constexpr VertexAttribute vec2() {
      return VertexAttribute{sizeof(float) * 2, VK_FORMAT_R32G32_SFLOAT};
   }

   static constexpr VertexAttribute vec3() {
      // TODO: Determine size properly through alignment
      return VertexAttribute{sizeof(float) * 4, VK_FORMAT_R32G32B32_SFLOAT};
   }
};

#endif // !VILLA_MATH_SIZES_H_
