#ifndef VKAD_GEOMETRY_BLUEPRINT_H_
#define VKAD_GEOMETRY_BLUEPRINT_H_

#include <vector>

#include "math/vec2.h"
#include "model.h"

namespace vkad {

class Shape {
public:
   inline const std::vector<Vec2> vertices() const {
      return vertices_;
   }

   Model to_model();

   Model extrude(float amount);

protected:
   std::vector<Vec2> vertices_;
};

} // namespace vkad

#endif // !VKAD_GEOMETRY_BLUEPRINT_H_
