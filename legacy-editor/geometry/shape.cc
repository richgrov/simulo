#include "shape.h"
#include "render/model.h"
#include "render/renderer.h"

using namespace simulo;

namespace {

static Model create_shape(std::vector<Vec2> points, float y, bool up) {
   std::vector<ModelVertex> vertices;
   std::vector<Renderer::IndexBufferType> indices;

   float y_norm = up ? 1 : -1;

   vertices.push_back({
       .pos = Vec3{0, y, 0},
       .norm = Vec3{0, y_norm, 0},
   });

   int boundary_verts = points.size();

   for (const Vec2 vec : points) {
      vertices.push_back({
          .pos = Vec3{vec.x(), y, vec.y()},
          .norm = Vec3{0, y_norm, 0},
      });

      Renderer::IndexBufferType this_vert = vertices.size() - 1;
      Renderer::IndexBufferType connected_vert = (this_vert % boundary_verts) + 1;

      if (up) {
         indices.insert(indices.end(), {0, this_vert, connected_vert});
      } else {
         indices.insert(indices.end(), {0, connected_vert, this_vert});
      }
   }

   return Model(std::move(vertices), std::move(indices));
}

} // namespace

Model Shape::to_model() {
   return create_shape(vertices_, 0, 1);
}

Model Shape::extrude(float amount) {
   Model bottom = create_shape(vertices_, 0, false);
   Model top = create_shape(vertices_, amount, true);
   bottom.add_all(top);

   int num_verts = bottom.vertices().size();

   for (int i = 0; i < vertices_.size(); ++i) {
      Renderer::IndexBufferType bottom_vert = bottom.vertices().size();
      Renderer::IndexBufferType top_vert = bottom_vert + 1;
      Renderer::IndexBufferType connected_bottom = bottom_vert + 2;
      Renderer::IndexBufferType connected_top = bottom_vert + 3;

      Vec2 pos = vertices_[i];
      Vec2 next_pos = vertices_[(i + 1) % vertices_.size()];

      Vec2 average_dir = (pos + next_pos).normalized();
      Vec3 norm{average_dir.x(), 0, average_dir.y()};

      bottom.vertices().insert(
          bottom.vertices().end(),
          {
              ModelVertex{
                  .pos = Vec3{pos.x(), 0, pos.y()},
                  .norm = norm,
              },
              ModelVertex{
                  .pos = Vec3{pos.x(), amount, pos.y()},
                  .norm = norm,
              },
              ModelVertex{
                  .pos = Vec3{next_pos.x(), 0, next_pos.y()},
                  .norm = norm,
              },
              ModelVertex{
                  .pos = Vec3{next_pos.x(), amount, next_pos.y()},
                  .norm = norm,
              },
          }
      );

      bottom.indices().insert(
          bottom.indices().end(),
          {
              bottom_vert,
              connected_bottom,
              top_vert,

              connected_bottom,
              connected_top,
              top_vert,
          }
      );
   }

   return bottom;
}
