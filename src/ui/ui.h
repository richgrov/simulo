#ifndef VKAD_UI_UI_H_
#define VKAD_UI_UI_H_

#include <array>

#include <vulkan/vulkan_core.h>

#include "math/attributes.h"
#include "math/mat4.h"
#include "math/vec2.h"
#include "math/vec3.h"

namespace vkad {

struct UiVertex {
   Vec3 pos;
   Vec2 tex_coord;

   static const std::array<VkVertexInputAttributeDescription, 2> kAttributes;
};

inline constexpr decltype(UiVertex::kAttributes) UiVertex::kAttributes = {
    VKAD_ATTRIBUTE(0, UiVertex, pos),
    VKAD_ATTRIBUTE(1, UiVertex, tex_coord),
};

struct UiUniform {
   Mat4 mvp;
   Vec3 color;
};

} // namespace vkad

#endif // !VKAD_UI_UI_H_
