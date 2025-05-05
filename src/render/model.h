#pragma once

#include "math/vector.h"
#include "renderer.h"

namespace simulo {

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

} // namespace simulo
