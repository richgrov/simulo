#ifndef VKAD_MESH_H_
#define VKAD_MESH_H_

#include "gpu/buffer.h"

#include <vector>

namespace vkad {

class Renderer;

template <class Vertex> class Mesh {
public:
   Mesh(std::vector<Vertex> &&vertices, std::vector<VertexIndexBuffer::IndexType> &&indices)
       : vertices_(vertices), indices_(indices) {}

   inline const std::vector<Vertex> &vertices() const {
      return vertices_;
   }

   inline const std::vector<VertexIndexBuffer::IndexType> &indices() const {
      return indices_;
   }

   inline int id() const {
      return id_;
   }

private:
   std::vector<Vertex> vertices_;
   std::vector<VertexIndexBuffer::IndexType> indices_;
   int id_;

   friend class vkad::Renderer;
};

} // namespace vkad

#endif // !VKAD_MESH_H_
