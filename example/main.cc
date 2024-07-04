#include <array>
#include <exception>
#include <iostream>

#include "gpu/buffer.h"
#include "gpu/gpu.h"
#include "math/attributes.h"
#include "math/vec2.h"
#include "math/vec3.h"
#include "util/rand.h"
#include "window/window.h" // IWYU pragma: export

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
      Window window("villa");
      Gpu gpu;

      gpu.init(window.vulkan_extensions());

      auto surface = window.create_surface(gpu.instance());
      int width = window.width();
      int height = window.height();
      gpu.connect_to_surface(surface, width, height);

      auto pipeline = gpu.create_pipeline<Vertex>();
      auto staging_buffer = gpu.create_staging_buffer(64 * 1024);

      std::vector<Vertex> vertices{
          {{0.0f, -0.5f}, {1.0f, 0.0f, 0.0f}},
          {{0.5f, 0.5f}, {0.0f, 1.0f, 0.0f}},
          {{-0.5f, 0.5f}, {0.0f, 0.0f, 1.0f}},
      };
      std::vector<IndexBuffer::IndexType> indices{
          0,
          1,
          2,
      };
      auto vertex_buffer = gpu.allocate_vertex_buffer<Vertex>(3);
      auto index_buffer = gpu.create_index_buffer(3);

      staging_buffer.upload_memory(vertices.data(), sizeof(Vertex) * vertices.size());
      gpu.buffer_copy(staging_buffer, vertex_buffer);
      staging_buffer.upload_memory(indices.data(), sizeof(IndexBuffer::IndexType) * indices.size());
      gpu.buffer_copy(staging_buffer, index_buffer);

      while (window.poll()) {
         if (window.left_clicking()) {
            float mouse_x = static_cast<float>(window.mouse_x());
            float mouse_y = static_cast<float>(window.mouse_y());

            float norm_x = mouse_x / width * 2.f - 1.f;
            float norm_y = mouse_y / height * 2.f - 1.f;

            vertices.push_back({{norm_x, norm_y - .01f}, {randf(), randf(), randf()}});
            vertices.push_back({{norm_x + .01f, norm_y + .01f}, {randf(), randf(), randf()}});
            vertices.push_back({{norm_x - .01f, norm_y + .01f}, {randf(), randf(), randf()}});

            IndexBuffer::IndexType index = indices.size();
            indices.push_back(index);
            indices.push_back(index + 1);
            indices.push_back(index + 2);

            staging_buffer.upload_memory(vertices.data(), sizeof(Vertex) * vertices.size());
            auto new_vertex_buf = gpu.allocate_vertex_buffer<Vertex>(vertices.size());
            gpu.buffer_copy(staging_buffer, new_vertex_buf);
            vertex_buffer = std::move(new_vertex_buf);

            staging_buffer.upload_memory(
                indices.data(), sizeof(IndexBuffer::IndexType) * indices.size()
            );
            auto new_index_buf = gpu.create_index_buffer(indices.size());
            gpu.buffer_copy(staging_buffer, new_index_buf);
            index_buffer = std::move(new_index_buf);
         }

         gpu.begin_draw(pipeline);
         gpu.draw(vertex_buffer, index_buffer);
         gpu.end_draw();

         gpu.wait_idle();
      }
   } catch (const std::exception &e) {
      std::cerr << "Unhandled exception: " << e.what() << "\n";
   }

   return 0;
}
