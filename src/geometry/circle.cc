#include "circle.h"

#include <cmath>
#include <numbers>

using namespace simulo;

Circle::Circle(float radius, int npoints) {
   float arc = (std::numbers::pi * 2) / npoints;
   for (int i = 0; i < npoints; ++i) {
      float angle = arc * i;
      Vec2 pos = Vec2{cosf(angle) * radius, sinf(angle) * radius};
      vertices_.push_back({pos});
   }
}
