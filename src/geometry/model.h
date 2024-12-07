#ifndef VKAD_GEOMETRY_MODEL_H_
#define VKAD_GEOMETRY_MODEL_H_

#include "gpu/vulkan/buffer.h"
#include "mesh.h"
#include "render/model.h"
#include "render/render_object.h"
#include "stl.h"

namespace vkad {

class Model : public Mesh<ModelVertex>, public RenderObject {
public:
   Model(std::vector<ModelVertex> &&vertices, std::vector<VertexIndexBuffer::IndexType> &&indices)
       : Mesh(std::move(vertices), std::move(indices)) {}

   std::vector<Triangle> to_stl_triangles() const;

   virtual inline Mat4 transform() const {
      return Mat4::identity();
   }
};

} // namespace vkad

#endif // !VKAD_GEOMETRY_MODEL_H_
