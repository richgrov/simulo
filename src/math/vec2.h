#ifndef VILLA_MATH_VEC2_H_
#define VILLA_MATH_VEC2_H_

namespace villa {

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

} // namespace villa

#endif // !VILLA_MATH_VEC2_H_
