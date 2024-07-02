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
      gpu.connect_to_surface(surface, window.width(), window.height());

      auto pipeline = gpu.create_pipeline<Vertex>();

      Vertex vertices[] = {
          {{0.0f, -0.5f}, {1.0f, 0.0f, 0.0f}},
          {{0.5f, 0.5f}, {0.0f, 1.0f, 0.0f}},
          {{-0.5f, 0.5f}, {0.0f, 0.0f, 1.0f}}
      };

      auto vertex_buffer = gpu.allocate_vertex_buffer<Vertex>(3);
      vertex_buffer.upload_memory(&vertices, sizeof(vertices));

      while (window.poll()) {
         gpu.draw(pipeline, vertex_buffer);
      }
   } catch (const std::exception &e) {
      std::cerr << "Unhandled exception: " << e.what() << "\n";
   }

   return 0;
}
