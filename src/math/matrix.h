#pragma once

#include <array>
#include <cmath>
#include <initializer_list>

#include "util/assert.h"
#include "vector.h"

namespace vkad {

template <size_t N, size_t M> struct Matrix {
   Matrix() : cols_{} {}

   Matrix(std::initializer_list<Vector<M>> rows) {
      VKAD_DEBUG_ASSERT(
          rows.size() == N, "matrix<{}, {}> initialized with {} rows", N, M, rows.size()
      );

      size_t i = 0;
      for (const Vector<M> row : rows) {
         for (size_t column = 0; column < M; ++column) {
            cols_[column][i] = row[column];
         }
         ++i;
      }
   }

   static Matrix identity()
      requires(N == M)
   {
      Matrix result;
      for (size_t i = 0; i < N; ++i) {
         result.cols_[i][i] = 1.0f;
      }
      return result;
   }

   static Matrix ortho(float left, float right, float top, float bottom, float near, float far) {
      // clang-format off
      return Matrix{
          {2.0f / (right - left), 0,                     0,                   -(right+left) / (right-left)},
          {0,                     2.0f / (bottom - top), 0,                   -(bottom+top) / (bottom-top)},
          {0,                     0,                     1.0f / (near - far), near/(near-far)},
          {0,                     0,                     0,                   1},
      };
      // clang-format on
   }

   static Matrix perspective(float aspect, float fov, float near, float far) {
      float tan_fov = tanf(fov / 2);
      float neg_depth = near - far;
      // clang-format off
      return Matrix{
          {1 / tan_fov * aspect, 0,            0,                 0},
          {0,                    -1 / tan_fov, 0,                 0},
          {0,                    0,            (far) / neg_depth, (near * far) / neg_depth},
          {0,                    0,            -1,                0},
      };
      // clang-format on
   }

   static Matrix translate(Vec3 v) {
      return Matrix{
          {1, 0, 0, v.x()},
          {0, 1, 0, v.y()},
          {0, 0, 1, v.z()},
          {0, 0, 0, 1},
      };
   }

   static Matrix rotate_x(float v) {
      // clang-format off
      return Matrix{
          {1, 0,       0,        0},
          {0, cosf(v), -sinf(v), 0},
          {0, sinf(v), cosf(v),  0},
          {0, 0,       0,        1},
      };
      // clang-format on
   }

   static Matrix rotate_y(float v) {
      // clang-format off
      return Matrix{
          {cosf(v), 0, -sinf(v), 0},
          {0,       1, 0,        0},
          {sinf(v), 0, cosf(v),  0},
          {0,       0, 0,        1},
      };
      // clang-format on
   }

   static Matrix rotate_z(float v) {
      // clang-format off
      return Matrix{
          {cosf(v), -sinf(v), 0, 0},
          {sinf(v), cosf(v),  0, 0},
          {0,       0,        1, 0},
          {0,       0,        0, 1},
      };
      // clang-format on
   }

   static Matrix scale(Vec3 v) {
      // clang-format off
      return Matrix{
          {v.x(), 0,     0,     0},
          {0,     v.y(), 0,     0},
          {0,     0,     v.z(), 0},
          {0,     0,     0,     1},
      };
      // clang-format on
   }

   inline Matrix operator*(const Matrix<N, M> &other) const
      requires(N == M)
   {
      Matrix result;
      for (size_t x = 0; x < N; ++x) {
         for (size_t y = 0; y < M; ++y) {
            result.cols_[y][x] = (*this)[x].dot(other.cols_[y]);
         }
      }
      return result;
   }

   Vector<N> operator*(const Vector<M> &v) {
      Vector<N> result;
      for (size_t i = 0; i < N; ++i) {
         result[i] = (*this)[i].dot(v);
      }
      return result;
   }

   inline Vector<M> operator[](size_t index) const {
      Vector<M> result;
      for (size_t i = 0; i < M; ++i) {
         result[i] = cols_[i][index];
      }
      return result;
   }

   inline Vector<N> &column(size_t index) {
      return cols_[index];
   }

   inline const Vector<N> &column(size_t index) const {
      return cols_[index];
   }

   Matrix<N - 1, M - 1> minor(size_t splice_row, size_t splice_column) const {
      Matrix<N - 1, M - 1> result;
      for (size_t row = 0; row < N; ++row) {
         if (row == splice_row) {
            continue;
         }

         size_t minor_row = row - (row > splice_row);

         for (size_t column = 0; column < M; ++column) {
            if (column == splice_column) {
               continue;
            }

            size_t minor_column = column - (column > splice_column);
            result.column(minor_column)[minor_row] = (*this)[row][column];
         }
      }

      return result;
   }

   float determinant() const
      requires(N == 1 && M == 1)
   {
      return cols_[0][0];
   }

   float determinant() const
      requires(N > 1 && M > 1)
   {
      float result = 0;
      for (size_t column = 0; column < M; ++column) {
         result += (column % 2 == 0 ? 1 : -1) * minor(0, column).determinant() * (*this)[0][column];
      }

      return result;
   }

private:
   std::array<Vector<N>, M> cols_;
};

using Mat2 = Matrix<2, 2>;
using Mat3 = Matrix<3, 3>;
using Mat4 = Matrix<4, 4>;

} // namespace vkad
