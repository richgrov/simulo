#ifndef VKAD_RENDER_VERTEX_H_
#define VKAD_RENDER_VERTEX_H_

#include "math/vec2.h"
#include "math/vec3.h"

namespace vkad {

struct UiVertex {
   Vec3 pos;
   Vec2 tex_coord;
};

struct UiUniform {
   Vec3 color;
};

} // namespace vkad

#endif // !VKAD_RENDER_VERTEX_H_
