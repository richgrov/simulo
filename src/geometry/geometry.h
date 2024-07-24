#ifndef VKAD_GEOMETRY_GEOMETRY_H_
#define VKAD_GEOMETRY_GEOMETRY_H_

#include <array>

#include <vulkan/vulkan_core.h>

#include "math/attributes.h"
#include "math/mat4.h"
#include "math/vec3.h"

namespace vkad {

struct ModelVertex {
   Vec3 pos;
   Vec3 norm;

   static const std::array<VkVertexInputAttributeDescription, 2> attributes;
};

inline constexpr decltype(ModelVertex::attributes) ModelVertex::attributes{
    VKAD_ATTRIBUTE(0, ModelVertex, pos),
    VKAD_ATTRIBUTE(1, ModelVertex, norm),
};

struct ModelUniform {
   Mat4 mvp;
   Vec3 color;
};

}; // namespace vkad

#endif // !VKAD_GEOMETRY_GEOMETRY_H_
