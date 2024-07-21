#include "shape.h"
#include "gpu/buffer.h"

using namespace vkad;

void Shape::to_mesh(
    std::vector<ModelVertex> &out_vertices, std::vector<VertexIndexBuffer::IndexType> &out_indices
) {
   out_vertices.push_back({
       .pos = Vec3(0, 0, 0),
       .norm = Vec3(0, 1, 0),
   });

   int boundary_verts = vertices_.size();

   for (const Vec2 vec : vertices_) {
      out_vertices.push_back({
          .pos = Vec3(vec.x, 0, vec.y),
          .norm = Vec3(0, 1, 0),
      });

      VertexIndexBuffer::IndexType this_vert = out_vertices.size() - 1;
      VertexIndexBuffer::IndexType connected_vert = (this_vert % boundary_verts) + 1;

      out_indices.insert(
          out_indices.end(),
          {
              0,
              this_vert,
              connected_vert,
          }
      );
   }
}
