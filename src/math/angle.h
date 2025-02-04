#pragma once

#include <numbers>

namespace vkad {

inline float deg_to_rad(float deg) {
   return deg / 180.0 * std::numbers::pi;
}

} // namespace vkad
