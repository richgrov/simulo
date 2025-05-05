#include <exception>
#include <iostream>

#include "app.h"

using namespace simulo;

int main(int argc, char **argv) {
   try {
      App app;

      while (app.poll()) {
         app.draw();
         app.renderer().wait_idle();
      }
   } catch (const std::exception &ex) {
      std::cerr << "unhandled exception: " << ex.what() << "\n";
   }

   return 0;
}
