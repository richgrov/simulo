#ifndef VKAD_MATH_VEC4_H_
#define VKAD_MATH_VEC4_H_

#include <algorithm>
#include <array>
#include <cstddef>
#include <initializer_list>
#include <type_traits>

#include <vulkan/vulkan_core.h>

#include "util/assert.h"

namespace vkad {

template <size_t N, size_t Alignment> struct alignas(Alignment) Vector {
   Vector() {}

   Vector(std::initializer_list<float> elements) {
      VKAD_DEBUG_ASSERT(
          elements.size() == N, "vector<{}> initialized with {} elements", N, elements.size()
      );
      std::copy(elements.begin(), elements.begin() + N, elements_.begin());
   }

   inline float operator[](int index) const {
      VKAD_DEBUG_ASSERT(index >= 0 && index < N, "attempt to index vector<{}>[{}]", N, index);
      return elements_[index];
   }

   inline float &operator[](int index) {
      VKAD_DEBUG_ASSERT(index >= 0 && index < N, "attempt to index vector<{}>[{}]", N, index);
      return elements_[index];
   }

   inline float dot(Vector<N, Alignment> other) const {
      float sum = 0;
      for (size_t i = 0; i < N; ++i) {
         sum += elements_[i] * other[i];
      }
      return sum;
   }

   Vector operator-() const {
      Vector result(*this);
      for (size_t i = 0; i < N; ++i) {
         result[i] = -result[i];
      }
      return result;
   }

   template <class = std::enable_if<N >= 1>::type> float &x() {
      return (*this)[0];
   }

   template <class = std::enable_if<N >= 1>::type> float x() const {
      return (*this)[0];
   }

   template <class = std::enable_if<N >= 2>::type> float &y() {
      return (*this)[1];
   }

   template <class = std::enable_if<N >= 2>::type> float y() const {
      return (*this)[1];
   }

   template <class = std::enable_if<N >= 3>::type> float &z() {
      return (*this)[2];
   }

   template <class = std::enable_if<N >= 3>::type> float z() const {
      return (*this)[2];
   }

   static constexpr VkFormat format() {
      static_assert(N == 3);
      if constexpr (N == 3) {
         return VK_FORMAT_R32G32B32_SFLOAT;
      }
   }

private:
   std::array<float, N> elements_;
};

using Vec4 = Vector<4, 16>;

} // namespace vkad

#endif // !VKAD_MATH_VEC4_H_
