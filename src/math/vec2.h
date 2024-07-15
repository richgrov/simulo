#ifndef VKAD_MATH_VEC2_H_
#define VKAD_MATH_VEC2_H_

namespace vkad {

struct Vec2 {
   Vec2() : x(0), y(0) {}
   Vec2(float x_, float y_) : x(x_), y(y_) {}

   inline bool operator==(Vec2 other) const {
      return x == other.x && y == other.y;
   }

   inline void operator+=(const Vec2 &other) {
      x += other.x;
      y += other.y;
   }

   inline Vec2 operator*(float factor) const {
      return {x * factor, y * factor};
   }

   float x;
   float y;
};

} // namespace vkad

#endif // !VKAD_MATH_VEC2_H_
