#ifndef VILLA_MATH_MAT3_H_
#define VILLA_MATH_MAT3_H_

#include "math/vec2.h"
#include "math/vec3.h"
namespace villa {

struct Mat3 {
   Mat3() : cells{} {}
   Mat3(Vec3 col1, Vec3 col2, Vec3 col3) : cells{col1, col2, col3} {}

   static Mat3 identity() {
      return Mat3({1, 0, 0}, {0, 1, 0}, {0, 0, 1});
   }

   static Mat3 translate(Vec2 v) {
      return Mat3({1, 0, 0}, {0, 1, 0}, {v.x, v.y, 1});
   }

   Vec3 cells[3];
};

} // namespace villa

#endif // !VILLA_MATH_MAT3_H_
