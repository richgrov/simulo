#include <exception>
#include <iostream>

#include "gpu/gpu.h"
#include "window/window.h" // IWYU pragma: export

using namespace villa;

typedef struct {
   float x;
   float y;
} Vec2;

typedef struct {
   float x;
   float y;
   float z;
} Vec3;

typedef struct {
   Vec2 pos;
   Vec3 color;
} Vertex;

int main(int argc, char **argv) {
   try {
      Window window("villa");
      Gpu gpu;

      gpu.init(window.vulkan_extensions());

      auto surface = window.create_surface(gpu.instance());
      gpu.connect_to_surface(surface, window.width(), window.height());

      auto pipeline = gpu.create_pipeline();

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
