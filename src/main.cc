#include "app.h"

using namespace vkad;

int main(int argc, char **argv) {
   App app;

   while (app.poll()) {
      app.draw();
      app.renderer().wait_idle();
   }

   return 0;
}
