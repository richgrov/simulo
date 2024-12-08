#include "wl_deleter.h"

#include <wayland-client-core.h>

using namespace vkad;

void WaylandDeleter::operator()(wl_display *display) {
   wl_display_disconnect(display);
}
