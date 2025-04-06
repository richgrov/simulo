#include "perception.h"

#include <iostream>
#include <thread>

using namespace simulo;

int main(int argc, char **argv) {
   try {
      Perception perception;
      perception.set_running(true);

      while (true) {
         std::this_thread::sleep_for(std::chrono::seconds(10));
      }
   } catch (const std::exception &e) {
      std::cerr << e.what() << std::endl;
      return 1;
   }
   return 0;
}
