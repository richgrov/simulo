#include "app.h"

using namespace villa;

App::App() : window_("villa") {
   gpu_.init(window_.vulkan_extensions());

   auto surface = window_.create_surface(gpu_.instance());
   gpu_.connect_to_surface(surface, window_.width(), window_.height());
}

void App::run() {
   while (window_.poll()) {
      gpu_.draw();
   }
}
