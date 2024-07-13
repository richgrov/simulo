#ifndef VILLA_MATH_VEC3_H_
#define VILLA_MATH_VEC3_H_

struct alignas(16) Vec3 {
   Vec3() : x(0), y(0), z(0) {}
   Vec3(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {}

   inline Vec3 operator-() const {
      return {-x, -y, -z};
   }

   float x;
   float y;
   float z;
};

#endif // !VILLA_MATH_VEC3_H_
