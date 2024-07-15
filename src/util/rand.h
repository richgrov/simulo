#ifndef VKAD_UTIL_RAND_H_
#define VKAD_UTIL_RAND_H_

#include <random>

namespace vkad {

static inline float randf() {
   return static_cast<float>(rand()) / static_cast<float>(RAND_MAX);
}

} // namespace vkad

#endif // !VKAD_UTIL_RAND_H_
