#ifndef VILLA_MATH_ANGLE_H_
#define VILLA_MATH_ANGLE_H_

#include <numbers>

namespace villa {

inline float deg_to_rad(float deg) {
   return deg / 180.0 * std::numbers::pi;
}

} // namespace villa

#endif // !VILLA_MATH_ANGLE_H_
