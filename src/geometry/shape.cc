#include "shape.h"
#include "geometry/geometry.h"
#include "gpu/buffer.h"

using namespace vkad;

ModelMesh Shape::to_mesh() {
   std::vector<ModelVertex> vertices;
   std::vector<VertexIndexBuffer::IndexType> indices;

   vertices.push_back({
       .pos = Vec3(0, 0, 0),
       .norm = Vec3(0, 1, 0),
   });

   int boundary_verts = vertices_.size();

   for (const Vec2 vec : vertices_) {
      vertices.push_back({
          .pos = Vec3(vec.x, 0, vec.y),
          .norm = Vec3(0, 1, 0),
      });

      VertexIndexBuffer::IndexType this_vert = vertices.size() - 1;
      VertexIndexBuffer::IndexType connected_vert = (this_vert % boundary_verts) + 1;

      indices.insert(
          indices.end(),
          {
              0,
              this_vert,
              connected_vert,
          }
      );
   }

   return ModelMesh(std::move(vertices), std::move(indices));
}
