#pragma once

#include <vector>

#include "math/vector.h"
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
