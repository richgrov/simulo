#include <exception>
#include <iostream>

#include "app.h"

#include "image/png.h"

using namespace vkad;

int main(int argc, char **argv) {
   std::string dir("/home/richard/Documents/FantasyEngine/sprites");
   // iterate all files in this directory and run this function for the data of each. AI!
   vkad::parse_png(std::span<const uint8_t> data)

       if (true) {
      return 0;
   }

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
