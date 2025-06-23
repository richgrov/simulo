#pragma once

#include "geometry/shape.h"

namespace simulo {

class Circle : public Shape {
public:
   Circle(float radius, int npoints);
};

} // namespace simulo
