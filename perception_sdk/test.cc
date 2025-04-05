#include "perception.h"

#include <iostream>

using namespace simulo;

int main(int argc, char **argv) {
   try {
      Perception perception;
      while (true) {
         perception.detect();
      }
   } catch (const std::exception &e) {
      std::cerr << e.what() << std::endl;
      return 1;
   }
   return 0;
}
