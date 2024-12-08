#ifndef VKAD_RENDER_MODEL_H_
#define VKAD_RENDER_MODEL_H_

#include "math/vec3.h"
#include "renderer.h" // IWYU pragma: export

namespace vkad {

struct ModelVertex {
   Vec3 pos;
   Vec3 norm;
};

struct ModelUniform {
   Vec3 color;

   static ModelUniform from_props(const MaterialProperties &props) {
      return ModelUniform{
          .color = props.get<Vec3>("color"),
      };
   }
};

} // namespace vkad

#endif // !VKAD_RENDER_MODEL_H_
