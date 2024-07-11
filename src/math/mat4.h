#ifndef VILLA_MATH_MAT4_H_
#define VILLA_MATH_MAT4_H_

#include "math/vec3.h"
#include "math/vec4.h"

namespace villa {

struct Mat4 {
   Mat4() : cols{} {}
   Mat4(Vec4 col1, Vec4 col2, Vec4 col3, Vec4 col4) : cols{col1, col2, col3, col4} {}

   static Mat4 identity() {
      return Mat4{
          {1, 0, 0, 0},
          {0, 1, 0, 0},
          {0, 0, 1, 0},
          {0, 0, 0, 1},
      };
   }

// Needed on win32
#undef near
#undef far

   static Mat4 ortho(float left, float right, float top, float bottom, float near, float far) {
      // clang-format off
      return Mat4{
          {2.0f / (right - left),        0,                            0,                      0},
          {0,                            2.0f / (bottom - top),        0,                      0},
          {0,                            0,                            1.0f / (near - far),    0},
          {-(right+left) / (right-left), -(bottom+top) / (bottom-top), near/(near-far),        1},
      };
      // clang-format on
   }

   static Mat4 translate(Vec3 v) {
      return Mat4{
          {1, 0, 0, 0},
          {0, 1, 0, 0},
          {0, 0, 1, 0},
          {v.x, v.y, v.z, 1},
      };
   }

   static Mat4 scale(Vec3 v) {
      return Mat4{
          {v.x, 0, 0, 0},
          {0, v.y, 0, 0},
          {0, 0, v.z, 0},
          {0, 0, 0, 1},
      };
   }

   inline Mat4 operator*(Mat4 other) const {
      Mat4 result;

      for (int x = 0; x < 4; ++x) {
         for (int y = 0; y < 4; ++y) {
            result.cols[y][x] = row(x).dot(other.cols[y]);
         }
      }

      return result;
   }

   inline Vec4 row(int index) const {
      return Vec4(cols[0][index], cols[1][index], cols[2][index], cols[3][index]);
   }

   Vec4 cols[4];
};

} // namespace villa

#endif // !VILLA_MATH_MAT4_H_
