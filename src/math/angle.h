#ifndef VKAD_MATH_ANGLE_H_
#define VKAD_MATH_ANGLE_H_

#include <numbers>

namespace vkad {

inline float deg_to_rad(float deg) {
   return deg / 180.0 * std::numbers::pi;
}

} // namespace vkad

#endif // !VKAD_MATH_ANGLE_H_
