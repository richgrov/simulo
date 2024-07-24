#ifndef VKAD_GEOMETRY_MODEL_H_
#define VKAD_GEOMETRY_MODEL_H_

#include "geometry/geometry.h"
#include "gpu/buffer.h"
#include "mesh.h"

namespace vkad {

class Model : public Mesh<ModelVertex> {
public:
   Model(std::vector<ModelVertex> &&vertices, std::vector<VertexIndexBuffer::IndexType> &&indices)
       : Mesh(std::move(vertices), std::move(indices)) {}
};

} // namespace vkad

#endif // !VKAD_GEOMETRY_MODEL_H_
