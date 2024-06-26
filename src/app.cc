#include "app.h"

using namespace villa;

App::App() : window_("villa") {
   gpu_.init(window_.vulkan_extensions());

}

void App::run() {
   while (window_.poll()) {
   }
}
