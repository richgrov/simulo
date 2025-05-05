#include "math/matrix.h"
#include "vendor/doctest.h"
#include <numbers>

using namespace simulo;

TEST_CASE("Matrix operations") {
   SUBCASE("Default constructor initializes to zero") {
      Mat4 m;
      for (int i = 0; i < 4; i++) {
         for (int j = 0; j < 4; j++) {
            CHECK(m[i][j] == 0.0f);
         }
      }
   }

   SUBCASE("Initializer list constructor") {
      Mat2 m{{1.0f, 2.0f}, {3.0f, 4.0f}};
      CHECK(m[0][0] == 1.0f);
      CHECK(m[0][1] == 2.0f);
      CHECK(m[1][0] == 3.0f);
      CHECK(m[1][1] == 4.0f);
   }

   SUBCASE("Identity matrix") {
      Mat3 m = Mat3::identity();
      for (int i = 0; i < 3; i++) {
         for (int j = 0; j < 3; j++) {
            CHECK(m[i][j] == doctest::Approx(i == j ? 1.0f : 0.0f));
         }
      }
   }

   SUBCASE("Translation matrix") {
      Vec3 translation{1.0f, 2.0f, 3.0f};
      Mat4 m = Mat4::translate(translation);
      Vec4 point{1.0f, 1.0f, 1.0f, 1.0f};

      Vec4 result = m * point;
      CHECK(result[0] == doctest::Approx(2.0f));
      CHECK(result[1] == doctest::Approx(3.0f));
      CHECK(result[2] == doctest::Approx(4.0f));
      CHECK(result[3] == doctest::Approx(1.0f));
   }

   SUBCASE("Scale matrix") {
      Vec3 scale{2.0f, 3.0f, 4.0f};
      Mat4 m = Mat4::scale(scale);
      Vec4 point{1.0f, 1.0f, 1.0f, 1.0f};

      Vec4 result = m * point;
      CHECK(result[0] == doctest::Approx(2.0f));
      CHECK(result[1] == doctest::Approx(3.0f));
      CHECK(result[2] == doctest::Approx(4.0f));
      CHECK(result[3] == doctest::Approx(1.0f));
   }

   SUBCASE("Rotation matrix X") {
      float angle = std::numbers::pi / 2.0f;
      Mat4 m = Mat4::rotate_x(angle);
      Vec4 point{0.0f, 1.0f, 0.0f, 1.0f};

      Vec4 result = m * point;
      CHECK(result[0] == doctest::Approx(0.0f).epsilon(0.0001f));
      CHECK(result[1] == doctest::Approx(0.0f).epsilon(0.0001f));
      CHECK(result[2] == doctest::Approx(1.0f).epsilon(0.0001f));
      CHECK(result[3] == doctest::Approx(1.0f));
   }

   SUBCASE("Rotation matrix Y") {
      float angle = std::numbers::pi / 2.0f;
      Mat4 m = Mat4::rotate_y(angle);
      Vec4 point{1.0f, 0.0f, 0.0f, 1.0f};

      Vec4 result = m * point;
      CHECK(result[0] == doctest::Approx(0.0f).epsilon(0.0001f));
      CHECK(result[1] == doctest::Approx(0.0f).epsilon(0.0001f));
      CHECK(result[2] == doctest::Approx(1.0f).epsilon(0.0001f));
      CHECK(result[3] == doctest::Approx(1.0f));
   }

   SUBCASE("Rotation matrix Z") {
      float angle = std::numbers::pi / 2.0f;
      Mat4 m = Mat4::rotate_z(angle);
      Vec4 point{1.0f, 0.0f, 0.0f, 1.0f};

      Vec4 result = m * point;
      CHECK(result[0] == doctest::Approx(0.0f).epsilon(0.0001f));
      CHECK(result[1] == doctest::Approx(1.0f).epsilon(0.0001f));
      CHECK(result[2] == doctest::Approx(0.0f).epsilon(0.0001f));
      CHECK(result[3] == doctest::Approx(1.0f));
   }

   SUBCASE("Matrix multiplication") {
      Mat2 a{{1.0f, 2.0f}, {3.0f, 4.0f}};
      Mat2 b{{5.0f, 6.0f}, {7.0f, 8.0f}};

      Mat2 result = a * b;
      CHECK(result[0][0] == doctest::Approx(19.0f));
      CHECK(result[0][1] == doctest::Approx(22.0f));
      CHECK(result[1][0] == doctest::Approx(43.0f));
      CHECK(result[1][1] == doctest::Approx(50.0f));
   }

   SUBCASE("Matrix minor") {
      Mat3 m{{1.0f, 2.0f, 3.0f}, {4.0f, 5.0f, 6.0f}, {7.0f, 8.0f, 9.0f}};

      Mat2 minor = m.minor(0, 0);
      CHECK(minor[0][0] == doctest::Approx(5.0f));
      CHECK(minor[0][1] == doctest::Approx(6.0f));
      CHECK(minor[1][0] == doctest::Approx(8.0f));
      CHECK(minor[1][1] == doctest::Approx(9.0f));

      minor = m.minor(1, 1);
      CHECK(minor[0][0] == doctest::Approx(1.0f));
      CHECK(minor[0][1] == doctest::Approx(3.0f));
      CHECK(minor[1][0] == doctest::Approx(7.0f));
      CHECK(minor[1][1] == doctest::Approx(9.0f));
   }

   SUBCASE("Matrix determinant") {
      Mat2 m2{{1.0f, 2.0f}, {3.0f, 4.0f}};
      CHECK(m2.determinant() == doctest::Approx(-2.0f));

      Mat3 m3{{1.0f, 2.0f, 3.0f}, {4.0f, 5.0f, 6.0f}, {7.0f, 8.0f, 9.0f}};
      CHECK(m3.determinant() == doctest::Approx(0.0f));

      Mat3 m3b{{2.0f, -3.0f, 1.0f}, {2.0f, 0.0f, -1.0f}, {1.0f, 4.0f, 5.0f}};
      CHECK(m3b.determinant() == doctest::Approx(49.0f));
   }

   SUBCASE("Matrix transpose") {
      Mat3 m{{1.0f, 2.0f, 3.0f}, {4.0f, 5.0f, 6.0f}, {7.0f, 8.0f, 9.0f}};

      Mat3 mt = m.transposed();

      CHECK(mt[0][0] == doctest::Approx(1.0f));
      CHECK(mt[0][1] == doctest::Approx(4.0f));
      CHECK(mt[0][2] == doctest::Approx(7.0f));

      CHECK(mt[1][0] == doctest::Approx(2.0f));
      CHECK(mt[1][1] == doctest::Approx(5.0f));
      CHECK(mt[1][2] == doctest::Approx(8.0f));

      CHECK(mt[2][0] == doctest::Approx(3.0f));
      CHECK(mt[2][1] == doctest::Approx(6.0f));
      CHECK(mt[2][2] == doctest::Approx(9.0f));
   }

   SUBCASE("Matrix inversion") {
      Mat2 m2{{4.0f, 7.0f}, {2.0f, 6.0f}};
      Mat2 inv2 = m2.inverted();
      Mat2 identity2 = m2 * inv2;

      CHECK(identity2[0][0] == doctest::Approx(1.0f).epsilon(0.0001f));
      CHECK(identity2[0][1] == doctest::Approx(0.0f).epsilon(0.0001f));
      CHECK(identity2[1][0] == doctest::Approx(0.0f).epsilon(0.0001f));
      CHECK(identity2[1][1] == doctest::Approx(1.0f).epsilon(0.0001f));

      Mat3 m3{{1.0f, 2.0f, 3.0f}, {0.0f, 1.0f, 4.0f}, {5.0f, 6.0f, 0.0f}};
      Mat3 inv3 = m3.inverted();
      Mat3 identity3 = m3 * inv3;

      for (int i = 0; i < 3; i++) {
         for (int j = 0; j < 3; j++) {
            CHECK(identity3[i][j] == doctest::Approx(i == j ? 1.0f : 0.0f).epsilon(0.0001f));
         }
      }

      Mat2 singular{{1.0f, 2.0f}, {2.0f, 4.0f}};
      CHECK_THROWS_AS(singular.inverted(), std::runtime_error);
   }
}
