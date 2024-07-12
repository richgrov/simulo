#include "angle.h"

#include "vendor/doctest.h"

#include <cmath>
#include <numbers>

using namespace villa;

constexpr float kEpsilon = 0.000001;

#define FUZZY_CHECK(a, b) CHECK(fabs((a) - (b)) < kEpsilon)

TEST_CASE("deg_to_rad") {
   FUZZY_CHECK(deg_to_rad(0), 0);
   FUZZY_CHECK(deg_to_rad(90), std::numbers::pi / 2);
   FUZZY_CHECK(deg_to_rad(180), std::numbers::pi);
   FUZZY_CHECK(deg_to_rad(270), 3 * std::numbers::pi / 2);
   FUZZY_CHECK(deg_to_rad(360), std::numbers::pi * 2);

   FUZZY_CHECK(deg_to_rad(-90), -std::numbers::pi / 2);
   FUZZY_CHECK(deg_to_rad(-180), -std::numbers::pi);
   FUZZY_CHECK(deg_to_rad(-270), -3 * std::numbers::pi / 2);
   FUZZY_CHECK(deg_to_rad(-360), -std::numbers::pi * 2);
}
