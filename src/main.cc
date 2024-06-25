#include "window/window.h" // IWYU pragma: export
#include <exception>
#include <iostream>

using namespace villa;

int main(int argc, char **argv) {
   try {
      Window window;

      while (window.poll()) {
      }
   } catch (const std::exception &e) {
      std::cerr << "Unhandled exception: " << e.what() << "\n";
   }
}
