#ifndef VKAD_MATH_VEC4_H_
#define VKAD_MATH_VEC4_H_

#include "util/assert.h"

namespace vkad {

struct alignas(16) Vec4 {
   Vec4() : x(0), y(0), z(0), w(0) {}
   Vec4(float x_, float y_, float z_, float w_) : x(x_), y(y_), z(z_), w(w_) {}

   inline float operator[](int index) const {
      switch (index) {
      case 0:
         return x;
      case 1:
         return y;
      case 2:
         return z;
      case 3:
         return w;
      default:
         VKAD_PANIC("invalid index {}", index);
      }
   }

   inline float &operator[](int index) {
      switch (index) {
      case 0:
         return x;
      case 1:
         return y;
      case 2:
         return z;
      case 3:
         return w;
      default:
         VKAD_PANIC("invalid index {}", index);
      }
   }

   inline float dot(Vec4 other) const {
      return x * other.x + y * other.y + z * other.z + w * other.w;
   }

   float x;
   float y;
   float z;
   float w;
};

} // namespace vkad

#endif // !VKAD_MATH_VEC4_H_
