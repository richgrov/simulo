#ifndef VKAD_GEOMETRY_GEOMETRY_H_
#define VKAD_GEOMETRY_GEOMETRY_H_

#include <array>

#include "math/attributes.h"
#include "math/mat4.h"
#include "math/vec3.h"

namespace vkad {

struct ModelVertex {
   Vec3 pos;
   Vec3 norm;

   static constexpr std::array<VertexAttribute, 2> attributes{
       VertexAttribute::vec3(),
       VertexAttribute::vec3(),
   };
};

struct ModelUniform {
   Mat4 mvp;
   Vec3 color;
};

}; // namespace vkad

#endif // !VKAD_GEOMETRY_GEOMETRY_H_
