#ifndef VKAD_RENDER_MODEL_H_
#define VKAD_RENDER_MODEL_H_

#include "math/mat4.h"
#include "math/vec3.h"

namespace vkad {

struct ModelVertex {
   Vec3 pos;
   Vec3 norm;
};

struct ModelUniform {
   Mat4 mvp;
   Vec3 color;
};

} // namespace vkad

#endif // !VKAD_RENDER_MODEL_H_
