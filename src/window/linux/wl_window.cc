#include "wl_window.h"

#include "gpu/instance.h"

#include <cstring>
#include <stdexcept>
#include <stdint.h>
#include <wayland-client-core.h>
#include <wayland-client-protocol.h>
#include <wayland-client.h>

using namespace vkad;

void vkad::handle_global(
    void *user_ptr, wl_registry *registry, uint32_t id, const char *interface, uint32_t version
) {
   WaylandWindow *window = reinterpret_cast<WaylandWindow *>(user_ptr);

   if (std::strcmp(interface, "wl_compositor") == 0) {
      void *compositor = wl_registry_bind(registry, id, &wl_compositor_interface, 4);
      window->compositor_ = reinterpret_cast<wl_compositor *>(compositor);
   }
}

namespace {

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
   wl_registry_add_listener(registry, &registry_listener, this);
   wl_display_roundtrip(display_);

   if (compositor_ == nullptr) {
      throw std::runtime_error("compositor was not initialized");
   }

   surface_ = wl_compositor_create_surface(compositor_);
}

WaylandWindow::~WaylandWindow() {
   wl_surface_destroy(surface_);
   wl_display_disconnect(display_);
}

bool WaylandWindow::poll() {
   return false;
}
