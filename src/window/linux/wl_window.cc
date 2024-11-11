#include "wl_window.h"

#include "gpu/instance.h"
#include "gpu/status.h"
#include "xdg-shell-client-protocol.h"

#include <cstring>
#include <stdexcept>
#include <stdint.h>
#include <vulkan/vulkan_core.h>
#include <vulkan/vulkan_wayland.h>
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
   } else if (std::strcmp(interface, xdg_wm_base_interface.name) == 0) {
      void *xdg_base = wl_registry_bind(registry, id, &xdg_wm_base_interface, 1);
      window->xdg_base_ = reinterpret_cast<xdg_wm_base *>(xdg_base);
   }
}

namespace {

void global_remove(void *user_ptr, wl_registry *registry, uint32_t name) {}

const struct wl_registry_listener registry_listener = {
    .global = handle_global,
    .global_remove = global_remove,
};

VkSurfaceKHR create_surface(wl_display *display, wl_surface *surface, VkInstance vk_instance) {
   VkWaylandSurfaceCreateInfoKHR vk_create_info = {
       .sType = VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
       .display = display,
       .surface = surface,
   };

   VkSurfaceKHR result;
   VKAD_VK(vkCreateWaylandSurfaceKHR(vk_instance, &vk_create_info, nullptr, &result));
   return result;
}

} // namespace

WaylandWindow::WaylandWindow(const Instance &vk_instance, const char *title) {
   display_ = wl_display_connect(NULL);
   if (!display_) {
      throw std::runtime_error("couldn't connect to Wayland display");
   }

   wl_registry *registry = wl_display_get_registry(display_);
   wl_registry_add_listener(registry, &registry_listener, this);
   wl_display_roundtrip(display_);

   if (compositor_ == nullptr || xdg_base_ == nullptr) {
      throw std::runtime_error("compositor or xdg_wm_base were not initialized");
   }

   surface_ = wl_compositor_create_surface(compositor_);
   vk_surface_ = create_surface(display_, surface_, vk_instance.handle());

   xdg_surface *surf = xdg_wm_base_get_xdg_surface(xdg_base_, surface_);
   xdg_surface_get_toplevel(surf);
   wl_surface_commit(surface_);
}

WaylandWindow::~WaylandWindow() {
   xdg_toplevel_destroy(xdg_toplevel_);
   xdg_surface_destroy(xdg_surface_);
   xdg_wm_base_destroy(xdg_base_);
   wl_surface_destroy(surface_);
   wl_display_disconnect(display_);
}

bool WaylandWindow::poll() {
   wl_display_dispatch_pending(display_);

   if (wl_display_flush(display_) == -1) {
      throw std::runtime_error("wl_display_flush failed");
   }

   return true;
}
