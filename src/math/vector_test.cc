#include "math/vector.h"
#include "vendor/doctest.h"

using namespace vkad;

TEST_CASE("Vector construction and basic operations") {
   SUBCASE("Default construction creates zero vector") {
      Vec3 v;
      CHECK(v.x() == 0.0f);
      CHECK(v.y() == 0.0f);
      CHECK(v.z() == 0.0f);
   }

   SUBCASE("Construction from initializer list") {
      Vec3 v{1.0f, 2.0f, 3.0f};
      CHECK(v.x() == 1.0f);
      CHECK(v.y() == 2.0f);
      CHECK(v.z() == 3.0f);
   }

   SUBCASE("Vector addition") {
      Vec3 v1{1.0f, 2.0f, 3.0f};
      Vec3 v2{4.0f, 5.0f, 6.0f};
      Vec3 sum = v1 + v2;
      CHECK(sum.x() == 5.0f);
      CHECK(sum.y() == 7.0f);
      CHECK(sum.z() == 9.0f);
   }

   SUBCASE("Vector negation") {
      Vec3 v{1.0f, -2.0f, 3.0f};
      Vec3 neg = -v;
      CHECK(neg.x() == -1.0f);
      CHECK(neg.y() == 2.0f);
      CHECK(neg.z() == -3.0f);
   }
}

TEST_CASE("Vector mathematical operations") {
   SUBCASE("Vector length") {
      Vec3 v{3.0f, 4.0f, 12.0f};
      CHECK(v.length() == 13.0f);
   }

   SUBCASE("Vector normalization") {
      Vec3 v{3.0f, 4.0f, 12.0f};
      Vec3 norm = v.normalized();
      CHECK(norm.x() == doctest::Approx(3.0f / 13.0f));
      CHECK(norm.y() == doctest::Approx(4.0f / 13.0f));
      CHECK(norm.z() == doctest::Approx(12.0f / 13.0f));
   }

   SUBCASE("Dot product") {
      Vec3 v1{1.0f, 2.0f, 3.0f};
      Vec3 v2{4.0f, 5.0f, 6.0f};
      CHECK(v1.dot(v2) == 32.0f);
   }

   SUBCASE("Basic cross product") {
      Vec3 v1{1.0f, 0.0f, 0.0f};
      Vec3 v2{0.0f, 1.0f, 0.0f};
      Vec3 cross = v1.cross(v2);
      CHECK(cross.x() == 0.0f);
      CHECK(cross.y() == 0.0f);
      CHECK(cross.z() == 1.0f);
   }

   SUBCASE("Scalar multiplication") {
      Vec3 v{1.0f, 2.0f, 3.0f};
      Vec3 result = v * 2.0f;
      CHECK(result.x() == 2.0f);
      CHECK(result.y() == 4.0f);
      CHECK(result.z() == 6.0f);
   }

   SUBCASE("Scalar division") {
      Vec3 v{2.0f, 4.0f, 6.0f};
      Vec3 result = v / 2.0f;
      CHECK(result.x() == 1.0f);
      CHECK(result.y() == 2.0f);
      CHECK(result.z() == 3.0f);
   }
}

TEST_CASE("Vector equality") {
   SUBCASE("Equal vectors") {
      Vec3 v1{1.0f, 2.0f, 3.0f};
      Vec3 v2{1.0f, 2.0f, 3.0f};
      CHECK(v1 == v2);
   }

   SUBCASE("Unequal vectors") {
      Vec3 v1{1.0f, 2.0f, 3.0f};
      Vec3 v2{1.0f, 2.0f, 4.0f};
      CHECK_FALSE(v1 == v2);
   }
}
