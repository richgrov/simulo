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
   static UiUniform from_props(const MaterialProperties &props) {
      return UiUniform{};
   }
};

} // namespace simulo
