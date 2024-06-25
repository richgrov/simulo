#include "app.h"

using namespace villa;

App::App() : window_("villa") {}

void App::run() {
   while (window_.poll()) {
   }
}
