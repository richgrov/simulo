#ifndef VILLA_MATH_VEC4_H_
#define VILLA_MATH_VEC4_H_

namespace villa {

struct alignas(16) Vec4 {
   float x;
   float y;
   float z;
   float w;
};

} // namespace villa

#endif // !VILLA_MATH_VEC4_H_
