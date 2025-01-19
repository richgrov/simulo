#ifndef VKAD_MATH_VEC4_H_
#define VKAD_MATH_VEC4_H_

#include <algorithm>
#include <array>
#include <initializer_list>

#include "util/assert.h"

namespace vkad {

struct alignas(16) Vec4 {
   Vec4() {}

   Vec4(std::initializer_list<float> elements) {
      VKAD_DEBUG_ASSERT(elements.size() == 4, "vec4 initialized with {} elements", elements.size());
      std::copy(elements.begin(), elements.begin() + 4, elements_.begin());
   }

   inline float operator[](int index) const {
      VKAD_DEBUG_ASSERT(index >= 0 && index < 4, "attempt to index vec4[{}]", index);
      return elements_[index];
   }

   inline float &operator[](int index) {
      VKAD_DEBUG_ASSERT(index >= 0 && index < 4, "attempt to index vec4[{}]", index);
      return elements_[index];
   }

   inline float dot(Vec4 other) const {
      return elements_[0] * other[0] + elements_[1] * other[1] + elements_[2] * other[2] +
             elements_[3] * other[3];
   }

private:
   std::array<float, 4> elements_;
};

} // namespace vkad

#endif // !VKAD_MATH_VEC4_H_
