#include <array>
#include <exception>
#include <iostream>

#include "gpu/gpu.h"
#include "math/attributes.h"
#include "math/vec2.h"
#include "math/vec3.h"
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

      std::vector<Vertex> vertices{
          {{0.0f, -0.5f}, {1.0f, 0.0f, 0.0f}},
          {{0.5f, 0.5f}, {0.0f, 1.0f, 0.0f}},
          {{-0.5f, 0.5f}, {0.0f, 0.0f, 1.0f}},
      };
      auto vertex_buffer = gpu.allocate_vertex_buffer<Vertex>(vertices.size());
      vertex_buffer.upload_memory(vertices.data(), vertices.size() * sizeof(Vertex));

      while (window.poll()) {
         if (window.left_clicking()) {
            float mouse_x = static_cast<float>(window.mouse_x());
            float mouse_y = static_cast<float>(window.mouse_y());

            float norm_x = mouse_x / width * 2.f - 1.f;
            float norm_y = mouse_y / height * 2.f - 1.f;

            vertices.push_back({{norm_x, norm_y - .01f}, {1.0, 1.0, 1.0}});
            vertices.push_back({{norm_x + .01f, norm_y + .01f}, {1.0, 1.0, 1.0}});
            vertices.push_back({{norm_x - .01f, norm_y + .01f}, {1.0, 1.0, 1.0}});

            vertex_buffer = std::move(gpu.allocate_vertex_buffer<Vertex>(vertices.size()));
            vertex_buffer.upload_memory(vertices.data(), vertices.size() * sizeof(Vertex));
         }

         gpu.draw(pipeline, vertex_buffer);
         gpu.wait_idle();
      }
   } catch (const std::exception &e) {
      std::cerr << "Unhandled exception: " << e.what() << "\n";
   }

   return 0;
}
