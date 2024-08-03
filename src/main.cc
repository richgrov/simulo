#include <exception>
#include <iostream>

#include "app.h"

using namespace vkad;

int main(int argc, char **argv) {
   try {
      App app;

      while (app.poll()) {
         app.draw();
         app.renderer().wait_idle();
      }
   } catch (const std::exception &e) {
      std::cerr << "Unhandled exception: " << e.what() << "\n";
   }

   return 0;
}
