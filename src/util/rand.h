#ifndef VILLA_UTIL_RAND_H_
#define VILLA_UTIL_RAND_H_

#include <random>

namespace villa {

static inline float randf() {
   return static_cast<float>(rand()) / static_cast<float>(RAND_MAX);
}

} // namespace villa

#endif // !VILLA_UTIL_RAND_H_
