#pragma once

#include <random>

namespace simulo {

static inline float randf() {
   return static_cast<float>(rand()) / static_cast<float>(RAND_MAX);
}

} // namespace simulo
