#include <array>
#include <exception>
#include <iostream>

#include "game.h"
#include "gpu/buffer.h"
#include "math/attributes.h"
#include "math/vec2.h"
#include "math/vec3.h"
#include "util/array.h"
#include "util/rand.h"

using namespace villa;

struct Vertex {
   Vec2 pos;
   Vec3 color;

   static constexpr std::array<VertexAttribute, 2> attributes{
       VertexAttribute::vec2(),
       VertexAttribute::vec3(),
   };
};

int main(int argc, char **argv) {
   try {
      Game game("villa");

      auto pipeline = game.create_pipeline<Vertex>();
      auto staging_buffer = game.create_staging_buffer(1024);

      auto uniform_buffer = game.create_uniform_buffer<Vec2>(1);
      auto descriptor_pool = game.create_descriptor_pool(pipeline);
      auto descriptor_set = descriptor_pool.allocate(uniform_buffer);

      Vec2 offset = {0.1, 0.1};
      uniform_buffer.upload_memory(&offset, sizeof(Vec2), 0);

      Vertex vertices[] = {
          {{0.0f, -0.5f}, {1.0f, 0.0f, 0.0f}},
          {{0.5f, 0.5f}, {0.0f, 1.0f, 0.0f}},
          {{-0.5f, 0.5f}, {0.0f, 0.0f, 1.0f}},
      };
      VertexIndexBuffer::IndexType indices[] = {0, 1, 2};

      auto mesh_buffer = game.create_vertex_index_buffer<Vertex>(3, 3);
      staging_buffer.upload_mesh(vertices, sizeof(vertices), indices, VILLA_ARRAY_LEN(indices));
      game.buffer_copy(staging_buffer, mesh_buffer);

      while (game.poll()) {
         /*if (game.left_clicking()) {
            float mouse_x = static_cast<float>(game.mouse_x());
            float mouse_y = static_cast<float>(game.mouse_y());

            float norm_x = mouse_x / game.width() * 2.f - 1.f;
            float norm_y = mouse_y / game.height() * 2.f - 1.f;

            vertices.push_back({{norm_x, norm_y - .01f}, {randf(), randf(), randf()}});
            vertices.push_back({{norm_x + .01f, norm_y + .01f}, {randf(), randf(), randf()}});
            vertices.push_back({{norm_x - .01f, norm_y + .01f}, {randf(), randf(), randf()}});

            IndexBuffer::IndexType index = indices.size();
            indices.push_back(index);
            indices.push_back(index + 1);
            indices.push_back(index + 2);

            staging_buffer.upload_memory(vertices.data(), sizeof(Vertex) * vertices.size());
            auto new_vertex_buf = game.create_vertex_buffer<Vertex>(vertices.size());
            game.buffer_copy(staging_buffer, new_vertex_buf);
            vertex_buffer = std::move(new_vertex_buf);

            staging_buffer.upload_memory(
                indices.data(), sizeof(IndexBuffer::IndexType) * indices.size()
            );
            auto new_index_buf = game.create_index_buffer(indices.size());
            game.buffer_copy(staging_buffer, new_index_buf);
            index_buffer = std::move(new_index_buf);
         }*/

         if (game.begin_draw(pipeline, descriptor_set)) {
            game.draw(mesh_buffer);
            game.end_draw();
         }

         game.wait_idle();
      }
   } catch (const std::exception &e) {
      std::cerr << "Unhandled exception: " << e.what() << "\n";
   }

   return 0;
}
