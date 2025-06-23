#include "wl_deleter.h"

#include <wayland-client-core.h>
#include <wayland-client-protocol.h>

using namespace simulo;

void WaylandDeleter::operator()(wl_display *display) {
   wl_display_disconnect(display);
}

void WaylandDeleter::operator()(wl_registry *registry) {
   wl_registry_destroy(registry);
}

void WaylandDeleter::operator()(wl_compositor *compositor) {
   wl_compositor_destroy(compositor);
}

void WaylandDeleter::operator()(wl_surface *surface) {
   wl_surface_destroy(surface);
}
