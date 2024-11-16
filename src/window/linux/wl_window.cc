#include "wl_window.h"

#include "gpu/instance.h"
#include "gpu/status.h"
#include "xdg-shell-client-protocol.h"

#include <cerrno>
#include <cstring>
#include <format>
#include <stdexcept>
#include <stdint.h>
#include <sys/mman.h>
#include <unistd.h>
#include <vulkan/vulkan_core.h>
#include <vulkan/vulkan_wayland.h>
#include <wayland-client-core.h>
#include <wayland-client-protocol.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

using namespace vkad;

void vkad::handle_global(
    void *user_ptr, wl_registry *registry, uint32_t id, const char *interface, uint32_t version
) {
   WaylandWindow *window = reinterpret_cast<WaylandWindow *>(user_ptr);

   if (std::strcmp(interface, wl_compositor_interface.name) == 0) {
      void *compositor = wl_registry_bind(registry, id, &wl_compositor_interface, 4);
      window->compositor_ = reinterpret_cast<wl_compositor *>(compositor);
      return;
   }

   if (std::strcmp(interface, xdg_wm_base_interface.name) == 0) {
      void *xdg_base = wl_registry_bind(registry, id, &xdg_wm_base_interface, 1);
      window->xdg_base_ = reinterpret_cast<xdg_wm_base *>(xdg_base);
      return;
   }

   if (std::strcmp(interface, wl_seat_interface.name) == 0) {
      void *seat = wl_registry_bind(registry, id, &wl_seat_interface, version);
      window->seat_ = reinterpret_cast<wl_seat *>(seat);
      return;
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

void kb_handler_enter(
    void *user_data, wl_keyboard *kb, uint32_t serial, wl_surface *surface, wl_array *keys
) {}

void kb_handler_leave(void *user_data, wl_keyboard *kb, uint32_t serial, wl_surface *surface) {}

void kb_handler_key(
    void *user_data, wl_keyboard *kb, uint32_t serial, uint32_t time, uint32_t key, uint32_t state
) {}

void kb_handler_modifiers(
    void *user_data, wl_keyboard *kb, uint32_t serial, uint32_t mods_pressed, uint32_t mods_latched,
    uint32_t mods_locked, uint32_t group
) {}

void kb_handler_repeat_info(void *user_data, wl_keyboard *kb, int32_t rate, int32_t delay) {}

} // namespace

WaylandWindow::WaylandWindow(const Instance &vk_instance, const char *title)
    : vk_instance_(vk_instance), xkb_ctx_(xkb_context_new(XKB_CONTEXT_NO_FLAGS)) {

   display_ = wl_display_connect(NULL);
   if (!display_) {
      throw std::runtime_error("couldn't connect to Wayland display");
   }

   registry_ = wl_display_get_registry(display_);
   wl_registry_add_listener(registry_, &registry_listener, this);
   wl_display_roundtrip(display_);

#define VERIFY_INIT(name)                                                                          \
   if ((name) == nullptr) {                                                                        \
      throw std::runtime_error(#name " was not initialized");                                      \
   }

   VERIFY_INIT(compositor_);
   VERIFY_INIT(xdg_base_);
   VERIFY_INIT(seat_);

   xdg_wm_base_listener xdg_listener = {
       .ping =
           [](void *user_ptr, xdg_wm_base *xdg_wm_base, uint32_t serial) {
              xdg_wm_base_pong(xdg_wm_base, serial);
           },
   };
   xdg_wm_base_add_listener(xdg_base_, &xdg_listener, this);

   surface_ = wl_compositor_create_surface(compositor_);
   vk_surface_ = create_surface(display_, surface_, vk_instance.handle());

   xdg_surface_ = xdg_wm_base_get_xdg_surface(xdg_base_, surface_);
   xdg_surface_listener xdg_surf_listener = {
       .configure =
           [](void *data, struct xdg_surface *xdg_surface, uint32_t serial) {
              auto window = reinterpret_cast<WaylandWindow *>(data);
              xdg_surface_ack_configure(xdg_surface, serial);
           },
   };
   xdg_surface_add_listener(xdg_surface_, &xdg_surf_listener, this);

   xdg_toplevel_ = xdg_surface_get_toplevel(xdg_surface_);
   xdg_toplevel_set_user_data(xdg_toplevel_, this);
   xdg_toplevel_listener toplevel_listener = {
       .configure = toplevel_configure,
       .close = toplevel_close,
   };
   xdg_toplevel_add_listener(xdg_toplevel_, &toplevel_listener, this);
   wl_surface_commit(surface_);

   keyboard_ = wl_seat_get_keyboard(seat_);
   wl_keyboard_listener kb_listener = {
       .keymap = kb_handler_keymap,
       .enter = kb_handler_enter,
       .leave = kb_handler_leave,
       .key = kb_handler_key,
       .modifiers = kb_handler_modifiers,
       .repeat_info = kb_handler_repeat_info,
   };
   wl_keyboard_add_listener(keyboard_, &kb_listener, this);
   wl_display_roundtrip(display_);
}

WaylandWindow::~WaylandWindow() {
   xkb_keymap_unref(keymap_);
   xkb_context_unref(xkb_ctx_);
   wl_keyboard_destroy(keyboard_);
   wl_seat_destroy(seat_);
   xdg_toplevel_destroy(xdg_toplevel_);
   xdg_surface_destroy(xdg_surface_);
   xdg_wm_base_destroy(xdg_base_);
   vkDestroySurfaceKHR(vk_instance_.handle(), vk_surface_, nullptr);
   wl_compositor_destroy(compositor_);
   wl_surface_destroy(surface_);
   wl_registry_destroy(registry_);
   wl_display_disconnect(display_);
}

bool WaylandWindow::poll() {
   while (wl_display_prepare_read(display_) != 0) {
      if (wl_display_dispatch_pending(display_) < 0) {
         throw std::runtime_error("wl_display_dispatch_pending failed");
      }
   }

   if (wl_display_read_events(display_) != 0) {
      int err = errno;
      throw std::runtime_error(std::format("wl_display_read_events failed: {}", err));
   }

   if (wl_display_flush(display_) == -1) {
      int err = errno;
      throw std::runtime_error(std::format("wl_display_flush failed: {}", err));
   }

   int display_err = wl_display_get_error(display_);
   if (display_err != 0) {
      throw std::runtime_error(std::format("wayland display error {}", display_err));
   }

   return open_;
}

void WaylandWindow::kb_handler_keymap(
    void *user_data, wl_keyboard *kb, uint32_t format, int32_t fd, uint32_t size
) {
   auto window_class = reinterpret_cast<WaylandWindow *>(user_data);

   void *keymap_str = mmap(nullptr, size, PROT_READ, MAP_SHARED, fd, 0);

   xkb_keymap_unref(window_class->keymap_);
   window_class->keymap_ = xkb_keymap_new_from_string(
       window_class->xkb_ctx_, reinterpret_cast<const char *>(keymap_str),
       XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS
   );

   xkb_state_unref(window_class->xkb_state_);
   window_class->xkb_state_ = xkb_state_new(window_class->keymap_);

   munmap(keymap_str, size);
   close(fd);
}

void WaylandWindow::toplevel_configure(
    void *user_data, struct xdg_toplevel *xdg_toplevel, int32_t width, int32_t height,
    struct wl_array *states
) {
   // TODO: Check if width/height are zero. If so, autonomously set window size
   WaylandWindow *window = reinterpret_cast<WaylandWindow *>(user_data);
   window->width_ = width;
   window->height_ = height;
}

void WaylandWindow::toplevel_close(void *user_ptr, struct xdg_toplevel *xdg_toplevel) {
   reinterpret_cast<WaylandWindow *>(user_ptr)->open_ = false;
}
