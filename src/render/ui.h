#pragma once

#include <string>

#include "math/vector.h"
#include "renderer.h"

namespace simulo {

struct UiVertex {
   Vec3 pos;
   Vec2 tex_coord;
};

struct UiUniform {
   Vec3 color;

   static UiUniform from_props(const MaterialProperties &props) {
      return UiUniform{
          .color = props.get<Vec3>("color"),
      };
   }
};

} // namespace simulo
