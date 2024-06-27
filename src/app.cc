#include "app.h"

using namespace villa;

App::App() : window_("villa") {
   gpu_.init(window_.vulkan_extensions());

   auto surface = window_.create_surface(gpu_.instance());
   gpu_.connect_to_surface(surface);
}

void App::run() {
   while (window_.poll()) {
   }
}
