#ifndef VKAD_GEOMETRY_BLUEPRINT_H_
#define VKAD_GEOMETRY_BLUEPRINT_H_

#include <vector>

#include "geometry/geometry.h"
#include "math/vec2.h"

namespace vkad {

class Shape {
public:
   inline const std::vector<Vec2> vertices() const {
      return vertices_;
   }

   ModelMesh to_mesh();

protected:
   std::vector<Vec2> vertices_;
};

} // namespace vkad

#endif // !VKAD_GEOMETRY_BLUEPRINT_H_
