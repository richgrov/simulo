#pragma once

#include <array>
#include <cmath>
#include <initializer_list>

#include "util/assert.h"
#include "util/os_detect.h"
#include "vector.h"

namespace simulo {

#ifdef VKAD_APPLE
#define SIMULO_Y_AXIS 1
#else
#define SIMULO_Y_AXIS -1
#endif

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

   static Matrix ortho(float width, float height, float near, float far) {
      float depth = far - near;
      // clang-format off
      return Matrix{
          {2.0f / width, 0,             0,            -1},
          {0,            2.0f / height, 0,            -SIMULO_Y_AXIS},
          {0,            0,             1.0f / depth, -near/depth},
          {0,            0,             0,            1},
      };
      // clang-format on
   }

   static Matrix perspective(float aspect, float fov, float near, float far) {
      float tan_fov = tanf(fov / 2);
      float depth = far - near;

      // clang-format off
      return Matrix{
          {1 / (aspect * tan_fov), 0,                       0,             0},
          {0,                      SIMULO_Y_AXIS / tan_fov, 0,             0},
          {0,                      0,                       far / depth,   -far * near / depth},
          {0,                      0,                       1,             0},
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

   static Matrix skew(Vec2 v) {
      return Matrix{
          {1, v.x()},
          {v.y(), 1},
          {0, 0, 1},
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

   Matrix transposed() const {
      Matrix result;
      for (size_t row = 0; row < N; ++row) {
         for (size_t column = 0; column < N; ++column) {
            result.cols_[row][column] = (*this)[row][column];
         }
      }
      return result;
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

   Matrix inverted() const
      requires(N == M)
   {
      float det = determinant();
      if (std::abs(det) < 1e-2f) {
         throw std::runtime_error("matrix is not invertible");
      }

      Matrix result;
      for (size_t row = 0; row < N; ++row) {
         for (size_t col = 0; col < M; ++col) {
            float cofactor = ((row + col) % 2 == 0 ? 1 : -1) * minor(row, col).determinant();
            result.column(col)[row] = cofactor / det;
         }
      }

      return result.transposed();
   }

private:
   std::array<Vector<N>, M> cols_;
};

using Mat2 = Matrix<2, 2>;
using Mat3 = Matrix<3, 3>;
using Mat4 = Matrix<4, 4>;

} // namespace simulo
