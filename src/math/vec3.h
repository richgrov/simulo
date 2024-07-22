#ifndef VKAD_MATH_VEC3_H_
#define VKAD_MATH_VEC3_H_

#include <vulkan/vulkan_core.h>

namespace vkad {

struct alignas(16) Vec3 {
   Vec3() : x(0), y(0), z(0) {}
   Vec3(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {}

   inline Vec3 operator-() const {
      return {-x, -y, -z};
   }

   float x;
   float y;
   float z;

   static constexpr VkFormat kFormat = VK_FORMAT_R32G32B32_SFLOAT;
};

} // namespace vkad

#endif // !VKAD_MATH_VEC3_H_
