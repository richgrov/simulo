#ifndef VKAD_GEOMETRY_MODEL_H_
#define VKAD_GEOMETRY_MODEL_H_

#include "geometry/geometry.h"
#include "gpu/buffer.h"
#include "mesh.h"
#include "stl.h"

namespace vkad {

class Model : public Mesh<ModelVertex> {
public:
   Model(std::vector<ModelVertex> &&vertices, std::vector<VertexIndexBuffer::IndexType> &&indices)
       : Mesh(std::move(vertices), std::move(indices)) {}

   std::vector<Triangle> to_stl_triangles() const;
};

} // namespace vkad

#endif // !VKAD_GEOMETRY_MODEL_H_
