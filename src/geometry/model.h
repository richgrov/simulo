#ifndef VKAD_GEOMETRY_MODEL_H_
#define VKAD_GEOMETRY_MODEL_H_

#include "gpu/vulkan/buffer.h"
#include "math/mat4.h"
#include "mesh.h"
#include "render/model.h"
#include "render/renderer.h" // IWYU pragma: export
#include "stl.h"

namespace vkad {

class Model : public Mesh<ModelVertex> {
public:
   Model(std::vector<ModelVertex> &&vertices, std::vector<VertexIndexBuffer::IndexType> &&indices)
       : Mesh(std::move(vertices), std::move(indices)) {}

   std::vector<Triangle> to_stl_triangles() const;

   inline Mat4 transform() const {
      return Mat4::identity();
   }

   RenderObject renderer_handle_;
};

} // namespace vkad

#endif // !VKAD_GEOMETRY_MODEL_H_
