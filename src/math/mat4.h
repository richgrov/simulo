#ifndef VILLA_MATH_MAT4_H_
#define VILLA_MATH_MAT4_H_

#include "math/vec3.h"
#include "math/vec4.h"

namespace villa {

struct Mat4 {
   Mat4() : cells{} {}
   Mat4(Vec4 col1, Vec4 col2, Vec4 col3, Vec4 col4) : cells{col1, col2, col3, col4} {}

   static Mat4 identity() {
      return Mat4{
          {1, 0, 0, 0},
          {0, 1, 0, 0},
          {0, 0, 1, 0},
          {0, 0, 0, 1},
      };
   }

   static Mat4 translate(Vec3 v) {
      return Mat4{
          {1, 0, 0, 0},
          {0, 1, 0, 0},
          {0, 0, 1, 0},
          {v.x, v.y, v.z, 1},
      };
   }

   Vec4 cells[4];
};

} // namespace villa

#endif // !VILLA_MATH_MAT4_H_
