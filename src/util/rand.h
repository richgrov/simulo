#pragma once

#include <random>

namespace vkad {

static inline float randf() {
   return static_cast<float>(rand()) / static_cast<float>(RAND_MAX);
}

} // namespace vkad
