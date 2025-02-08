#include <exception>
#include <iostream>
#include <filesystem>
#include <fstream>
#include <vector>

#include "app.h"
#include "image/png.h"

using namespace vkad;

int main(int argc, char **argv) {
   try {
       std::string dir("/home/richard/Documents/FantasyEngine/sprites");
       
       for (const auto& entry : std::filesystem::directory_iterator(dir)) {
           if (entry.path().extension() == ".png") {
               std::ifstream file(entry.path(), std::ios::binary);
               std::vector<uint8_t> data((std::istreambuf_iterator<char>(file)),
                                        std::istreambuf_iterator<char>());
               
               try {
                   vkad::parse_png(data);
                   std::cout << "Successfully parsed: " << entry.path().filename() << std::endl;
               } catch (const std::exception& e) {
                   std::cerr << "Failed to parse " << entry.path().filename() 
                            << ": " << e.what() << std::endl;
               }
           }
       }
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
