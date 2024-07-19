#ifndef VKAD_UI_UI_H_
#define VKAD_UI_UI_H_

#include <array>

#include "math/attributes.h"
#include "math/mat4.h"
#include "math/vec2.h"
#include "math/vec3.h"

namespace vkad {

struct UiVertex {
   Vec3 pos;
   Vec2 tex_coord;

   static constexpr std::array<VertexAttribute, 2> attributes{
       VertexAttribute::vec3(),
       VertexAttribute::vec2(),
   };
};

struct UiUniform {
   Mat4 mvp;
   Vec3 color;
};

} // namespace vkad

#endif // !VKAD_UI_UI_H_
