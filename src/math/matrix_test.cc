#include "math/matrix.h"
#include "vendor/doctest.h"
#include <numbers>

using namespace vkad;

TEST_CASE("Matrix operations") {
   SUBCASE("Default constructor initializes to zero") {
      Mat4 m;
      for (int i = 0; i < 4; i++) {
         for (int j = 0; j < 4; j++) {
            CHECK(m.row(i)[j] == 0.0f);
         }
      }
   }

   SUBCASE("Initializer list constructor") {
      Mat2 m{{1.0f, 2.0f}, {3.0f, 4.0f}};
      CHECK(m.row(0)[0] == 1.0f);
      CHECK(m.row(0)[1] == 2.0f);
      CHECK(m.row(1)[0] == 3.0f);
      CHECK(m.row(1)[1] == 4.0f);
   }

   SUBCASE("Identity matrix") {
      Mat3 m = Mat3::identity();
      for (int i = 0; i < 3; i++) {
         for (int j = 0; j < 3; j++) {
            CHECK(m.row(i)[j] == doctest::Approx(i == j ? 1.0f : 0.0f));
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
      CHECK(result.row(0)[0] == doctest::Approx(19.0f));
      CHECK(result.row(0)[1] == doctest::Approx(22.0f));
      CHECK(result.row(1)[0] == doctest::Approx(43.0f));
      CHECK(result.row(1)[1] == doctest::Approx(50.0f));
   }
}
