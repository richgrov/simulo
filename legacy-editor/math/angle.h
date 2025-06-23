#pragma once

#include <numbers>

namespace simulo {

inline float deg_to_rad(float deg) {
   return deg / 180.0 * std::numbers::pi;
}

} // namespace simulo
