#ifndef VKAD_GEOMETRY_CIRCLE_H_
#define VKAD_GEOMETRY_CIRCLE_H_

#include "geometry/shape.h"

namespace vkad {

class Circle : public Shape {
public:
   Circle(float radius, int npoints);
};

} // namespace vkad

#endif // !VKAD_GEOMETRY_CIRCLE_H_
