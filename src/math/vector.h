#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <initializer_list>

#ifndef __APPLE__
#include <vulkan/vulkan_core.h>
#endif

#include "util/assert.h"

namespace simulo {

template <size_t N, size_t Alignment = alignof(float[N])> struct alignas(Alignment) Vector {
   Vector() : elements_() {}

   constexpr Vector(std::initializer_list<float> elements) {
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

   float length() const {
      float result = 0;
      for (size_t i = 0; i < N; ++i) {
         result += elements_[i] * elements_[i];
      }
      return std::sqrtf(result);
   }

   Vector normalized() const {
      Vector result;

      float len = length();
      if (len == 0) {
         return result;
      }

      for (size_t i = 0; i < N; ++i) {
         result[i] = elements_[i] / len;
      }
      return result;
   }

   inline float dot(Vector<N, Alignment> other) const {
      float sum = 0;
      for (size_t i = 0; i < N; ++i) {
         sum += elements_[i] * other[i];
      }
      return sum;
   }

   Vector<3, Alignment> cross(Vector other) const
      requires(N == 3)
   {
      return Vector{
          elements_[1] * other[2] - elements_[2] * other[1],
          elements_[0] * other[2] - elements_[2] * other[0],
          elements_[0] * other[1] - elements_[1] * other[0],
      };
   }

   Vector operator+(Vector other) const {
      Vector result;
      for (size_t i = 0; i < N; ++i) {
         result[i] = elements_[i] + other[i];
      }
      return result;
   }

   Vector operator-() const {
      Vector result(*this);
      for (size_t i = 0; i < N; ++i) {
         result[i] = -result[i];
      }
      return result;
   }

   Vector operator*(float f) const {
      Vector result;
      for (size_t i = 0; i < N; ++i) {
         result[i] = elements_[i] * f;
      }
      return result;
   }

   Vector operator/(float f) const {
      Vector result;
      for (size_t i = 0; i < N; ++i) {
         result[i] = elements_[i] / f;
      }
      return result;
   }

   void operator+=(const Vector &other) {
      for (size_t i = 0; i < N; ++i) {
         elements_[i] += other.elements_[i];
      }
   }

   bool operator==(const Vector &other) const {
      for (size_t i = 0; i < N; ++i) {
         if (elements_[i] != other.elements_[i]) {
            return false;
         }
      }
      return true;
   }

   float &x()
      requires(N >= 1)
   {
      return (*this)[0];
   }

   float x() const
      requires(N >= 1)
   {
      return (*this)[0];
   }

   float &y()
      requires(N >= 2)
   {
      return (*this)[1];
   }

   float y() const
      requires(N >= 2)
   {
      return (*this)[1];
   }

   float &z()
      requires(N >= 3)
   {
      return (*this)[2];
   }

   float z() const
      requires(N >= 3)
   {
      return (*this)[2];
   }

   float w() const
      requires(N >= 4)
   {
      return (*this)[3];
   }

#ifndef __APPLE__
   static constexpr VkFormat format()
      requires(N >= 2 && N <= 3)
   {
      if constexpr (N == 2) {
         return VK_FORMAT_R32G32_SFLOAT;
      } else if constexpr (N == 3) {
         return VK_FORMAT_R32G32B32_SFLOAT;
      }
   }
#endif // !__APPLE__

private:
   std::array<float, N> elements_;
};

using Vec2 = Vector<2>;
using Vec3 = Vector<3, 16>;
using Vec4 = Vector<4>;

} // namespace simulo
