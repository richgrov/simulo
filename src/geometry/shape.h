#ifndef VKAD_GEOMETRY_BLUEPRINT_H_
#define VKAD_GEOMETRY_BLUEPRINT_H_

#include <vector>

#include "geometry/geometry.h"
#include "gpu/buffer.h"
#include "math/vec2.h"

namespace vkad {

class Shape {
public:
   inline const std::vector<Vec2> vertices() const {
      return vertices_;
   }

   void to_mesh(
       std::vector<ModelVertex> &out_vertices,
       std::vector<VertexIndexBuffer::IndexType> &out_indices
   );

protected:
   std::vector<Vec2> vertices_;
};

} // namespace vkad

#endif // !VKAD_GEOMETRY_BLUEPRINT_H_
