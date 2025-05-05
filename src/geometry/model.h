#pragma once

#include "math/matrix.h"
#include "mesh.h"
#include "render/model.h"
#include "render/renderer.h"
#include "stl.h"

namespace simulo {

class Model : public Mesh<ModelVertex> {
public:
   Model(std::vector<ModelVertex> &&vertices, std::vector<Renderer::IndexBufferType> &&indices)
       : Mesh(std::move(vertices), std::move(indices)) {}

   std::vector<Triangle> to_stl_triangles() const;

   inline Mat4 transform() const {
      return Mat4::identity();
   }

   RenderObject renderer_handle_;
   RenderMesh mesh_handle_;
};

} // namespace simulo
