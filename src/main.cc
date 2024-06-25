#include <exception>
#include <iostream>

#include "app.h"

using namespace villa;

int main(int argc, char **argv) {
   try {
      App app;
      app.run();
   } catch (const std::exception &e) {
      std::cerr << "Unhandled exception: " << e.what() << "\n";
   }

   return 0;
}
