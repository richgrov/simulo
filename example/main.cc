#include <exception>
#include <iostream>

#include "gpu/gpu.h"
#include "window/window.h" // IWYU pragma: export

using namespace villa;

int main(int argc, char **argv) {
   try {
      Window window("villa");
      Gpu gpu;

      gpu.init(window.vulkan_extensions());

      auto surface = window.create_surface(gpu.instance());
      gpu.connect_to_surface(surface, window.width(), window.height());

      while (window.poll()) {
         gpu.draw();
      }
   } catch (const std::exception &e) {
      std::cerr << "Unhandled exception: " << e.what() << "\n";
   }

   return 0;
}
