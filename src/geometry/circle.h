#pragma once

#include "geometry/shape.h"

namespace vkad {

class Circle : public Shape {
public:
   Circle(float radius, int npoints);
};

} // namespace vkad
