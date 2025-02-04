#pragma once

#include "math/vector.h"
#include <ostream>
#include <vector>

namespace vkad {

struct Triangle {
   Vec3 points[3];
   Vec3 normal;
};

void write_stl(const std::string &name, const std::vector<Triangle> triangles, std::ostream &out);

} // namespace vkad
