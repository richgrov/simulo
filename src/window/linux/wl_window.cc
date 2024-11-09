#include "wl_window.h"

#include "gpu/instance.h"

#include <iostream>
#include <stdexcept>
#include <stdint.h>
#include <wayland-client-core.h>
#include <wayland-client-protocol.h>
#include <wayland-client.h>

using namespace vkad;

namespace {

void handle_global(
    void *user_ptr, wl_registry *registry, uint32_t name, const char *interface, uint32_t version
) {}

void global_remove(void *user_ptr, wl_registry *registry, uint32_t name) {}

const struct wl_registry_listener registry_listener = {
    .global = handle_global,
    .global_remove = global_remove,
};

} // namespace

WaylandWindow::WaylandWindow(const Instance &vk_instance, const char *title) {
   display_ = wl_display_connect(NULL);
   if (!display_) {
      throw std::runtime_error("couldn't connect to Wayland display");
   }

   wl_registry *registry = wl_display_get_registry(display_);
   wl_registry_add_listener(registry, &registry_listener, NULL);
   wl_display_roundtrip(display_);
}

WaylandWindow::~WaylandWindow() {
   wl_display_disconnect(display_);
}

bool WaylandWindow::poll() {
   return false;
}
