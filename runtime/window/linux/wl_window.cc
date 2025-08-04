#include "wl_window.h"

#include "fractional-scale-protocol.h"
#include "gpu/vulkan/gpu.h"
#include "gpu/vulkan/status.h"
#include "pointer-constraints-unstable-v1-protocol.h"
#include "relative-pointer-unstable-v1-protocol.h"
#include "viewporter-protocol.h"
#include "window/linux/keys.h"
#include "xdg-shell-protocol.h"

#include <algorithm>
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
#include <xkbcommon/xkbcommon-keysyms.h>
#include <xkbcommon/xkbcommon.h>

using namespace simulo;

namespace {

uint8_t xkb_to_xinput2(xkb_keysym_t key) {
   switch (key) {
   case XKB_KEY_Escape:
      return VKAD_KEY_ESC;
   case XKB_KEY_Shift_L:
      return VKAD_KEY_SHIFT;
   case XKB_KEY_space:
      return VKAD_KEY_SPACE;
   case XKB_KEY_a:
   case XKB_KEY_A:
      return VKAD_KEY_A;
   case XKB_KEY_c:
   case XKB_KEY_C:
      return VKAD_KEY_C;
   case XKB_KEY_d:
   case XKB_KEY_D:
      return VKAD_KEY_D;
   case XKB_KEY_e:
   case XKB_KEY_E:
      return VKAD_KEY_E;
   case XKB_KEY_p:
   case XKB_KEY_P:
      return VKAD_KEY_P;
   case XKB_KEY_s:
   case XKB_KEY_S:
      return VKAD_KEY_S;
   case XKB_KEY_w:
   case XKB_KEY_W:
      return VKAD_KEY_W;

   default:
      return -1;
   }
}

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

WaylandWindow::WaylandWindow(const Gpu &vk_instance, const char *title)
    : vk_instance_(vk_instance), xkb_ctx_(xkb_context_new(XKB_CONTEXT_NO_FLAGS)) {

#define VERIFY_INIT(name)                                                                          \
   if ((name) == nullptr) {                                                                        \
      throw std::runtime_error(#name " was not initialized");                                      \
   }

   display_.reset(wl_display_connect(NULL));
   if (!display_.get()) {
      throw std::runtime_error("couldn't connect to Wayland display");
   }

   init_registry();

   VERIFY_INIT(compositor_);
   VERIFY_INIT(xdg_base_);
   VERIFY_INIT(seat_);
   VERIFY_INIT(keyboard_);
   VERIFY_INIT(pointer_);
   VERIFY_INIT(relative_pointer_manager_);
   VERIFY_INIT(fractional_scale_manager_);
   VERIFY_INIT(viewporter_);
   VERIFY_INIT(pointer_constraints_);

   init_xdg_wm_base();
   init_surfaces();
   init_toplevel(title);
   init_keyboard();
   init_pointer();
   init_relative_pointer();
   init_fractional_scale();
   init_viewport();

   mouse_lock_region_ = wl_compositor_create_region(compositor_.get());
   wl_region_add(mouse_lock_region_, 0, 0, 1, 1);

   wl_surface_commit(surface_.get());
   wl_display_roundtrip(display_.get());
}

WaylandWindow::~WaylandWindow() {
   if (locked_pointer_ != nullptr) {
      zwp_locked_pointer_v1_destroy(locked_pointer_);
   }
   zwp_pointer_constraints_v1_destroy(pointer_constraints_);
   wl_region_destroy(mouse_lock_region_);
   zwp_relative_pointer_v1_destroy(relative_pointer_);
   zwp_relative_pointer_manager_v1_destroy(relative_pointer_manager_);
   wp_fractional_scale_v1_destroy(fractional_scale_);
   wp_fractional_scale_manager_v1_destroy(fractional_scale_manager_);
   wp_viewporter_destroy(viewporter_);
   wp_viewport_destroy(viewport_);
   wl_pointer_destroy(pointer_);

   xkb_state_unref(xkb_state_);
   xkb_keymap_unref(keymap_);
   xkb_context_unref(xkb_ctx_);
   wl_keyboard_destroy(keyboard_);

   wl_seat_destroy(seat_);
   xdg_toplevel_destroy(xdg_toplevel_);
   xdg_surface_destroy(xdg_surface_);
   xdg_wm_base_destroy(xdg_base_);
   vkDestroySurfaceKHR(vk_instance_.instance(), vk_surface_, nullptr);
}

bool WaylandWindow::poll() {
   prev_pressed_keys_ = pressed_keys_;
   std::memset(typed_letters_, 0, sizeof(typed_letters_));
   next_typed_letter_ = 0;
   delta_mouse_x_ = 0;
   delta_mouse_y_ = 0;

   while (wl_display_prepare_read(display_.get()) != 0) {
      if (wl_display_dispatch_pending(display_.get()) < 0) {
         throw std::runtime_error("wl_display_dispatch_pending failed");
      }
   }

   if (wl_display_read_events(display_.get()) != 0) {
      int err = errno;
      throw std::runtime_error(std::format("wl_display_read_events failed: {}", err));
   }

   if (wl_display_flush(display_.get()) == -1) {
      int err = errno;
      throw std::runtime_error(std::format("wl_display_flush failed: {}", err));
   }

   int display_err = wl_display_get_error(display_.get());
   if (display_err != 0) {
      throw std::runtime_error(std::format("wayland display error {}", display_err));
   }

   return open_;
}

void WaylandWindow::set_capture_mouse(bool capture) {
   mouse_captured_ = capture;

   if (mouse_captured_) {
      if (locked_pointer_ != nullptr) {
         zwp_locked_pointer_v1_destroy(locked_pointer_);
      }

      locked_pointer_ = zwp_pointer_constraints_v1_lock_pointer(
          pointer_constraints_, surface_.get(), pointer_, mouse_lock_region_,
          ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_ONESHOT
      );
      init_locked_pointer();
   }
}

void WaylandWindow::init_registry() {
   registry_.reset(wl_display_get_registry(display_.get()));

   static constexpr wl_registry_listener registry_listener = {
       .global =
           [](void *user_ptr, wl_registry *registry, uint32_t id, const char *interface,
              uint32_t version) {
              WaylandWindow *window = reinterpret_cast<WaylandWindow *>(user_ptr);

              if (std::strcmp(interface, wl_compositor_interface.name) == 0) {
                 void *compositor = wl_registry_bind(registry, id, &wl_compositor_interface, 4);
                 window->compositor_.reset(reinterpret_cast<wl_compositor *>(compositor));
                 return;
              }

              if (std::strcmp(interface, xdg_wm_base_interface.name) == 0) {
                 void *xdg_base = wl_registry_bind(registry, id, &xdg_wm_base_interface, 1);
                 window->xdg_base_ = reinterpret_cast<xdg_wm_base *>(xdg_base);
                 return;
              }

              if (std::strcmp(interface, wp_fractional_scale_manager_v1_interface.name) == 0) {
                 void *fractional_scale = wl_registry_bind(
                     registry, id, &wp_fractional_scale_manager_v1_interface, version
                 );
                 window->fractional_scale_manager_ =
                     reinterpret_cast<wp_fractional_scale_manager_v1 *>(fractional_scale);
                 return;
              }

              if (std::strcmp(interface, wp_viewporter_interface.name) == 0) {
                 void *viewporter =
                     wl_registry_bind(registry, id, &wp_viewporter_interface, version);
                 window->viewporter_ = reinterpret_cast<wp_viewporter *>(viewporter);
                 return;
              }

              if (std::strcmp(interface, wl_seat_interface.name) == 0) {
                 void *seat = wl_registry_bind(registry, id, &wl_seat_interface, version);
                 window->seat_ = reinterpret_cast<wl_seat *>(seat);
                 window->init_seat();
                 return;
              }

              if (std::strcmp(interface, zwp_relative_pointer_manager_v1_interface.name) == 0) {
                 void *relative_pointer = wl_registry_bind(
                     registry, id, &zwp_relative_pointer_manager_v1_interface, version
                 );
                 window->relative_pointer_manager_ =
                     reinterpret_cast<zwp_relative_pointer_manager_v1 *>(relative_pointer);
                 return;
              }

              if (std::strcmp(interface, zwp_pointer_constraints_v1_interface.name) == 0) {
                 void *pointer_constraints =
                     wl_registry_bind(registry, id, &zwp_pointer_constraints_v1_interface, version);
                 window->pointer_constraints_ =
                     reinterpret_cast<zwp_pointer_constraints_v1 *>(pointer_constraints);
                 return;
              }
           },
       .global_remove = [](void *user_ptr, wl_registry *registry, uint32_t name) {},
   };
   wl_registry_add_listener(registry_.get(), &registry_listener, this);

   wl_display_roundtrip(display_.get());
   wl_display_roundtrip(display_.get()); // again so the wl_seat listener is run
}

void WaylandWindow::init_xdg_wm_base() {
   static constexpr xdg_wm_base_listener xdg_listener = {
       .ping = [](void *user_ptr, xdg_wm_base *xdg_wm_base, uint32_t serial) {
          xdg_wm_base_pong(xdg_wm_base, serial);
       },
   };
   xdg_wm_base_add_listener(xdg_base_, &xdg_listener, this);
}

void WaylandWindow::init_surfaces() {
   surface_.reset(wl_compositor_create_surface(compositor_.get()));

   static constexpr wl_surface_listener surface_listener = {
       .enter = [](void *user_data, wl_surface *surface, wl_output *) {},
       .leave = [](void *user_data, wl_surface *surface, wl_output *) {},
       .preferred_buffer_scale =
           [](void *user_data, wl_surface *surface, int32_t scale) {
              WaylandWindow *window = reinterpret_cast<WaylandWindow *>(user_data);
              window->scale_ = scale * 120;
           },
       .preferred_buffer_transform = [](void *user_data, wl_surface *surface, uint32_t) {},
   };
   wl_surface_add_listener(surface_.get(), &surface_listener, this);

   xdg_surface_ = xdg_wm_base_get_xdg_surface(xdg_base_, surface_.get());
   static constexpr xdg_surface_listener xdg_surf_listener = {
       .configure = [](void *data, struct xdg_surface *xdg_surface, uint32_t serial) {
          auto window = reinterpret_cast<WaylandWindow *>(data);
          float scale = (float)window->scale() / 120.0;
          float logicalWidth = (float)window->width() / scale;
          float logicalHeight = (float)window->height() / scale;
          wp_viewport_set_destination(
              window->viewport_, (int32_t)logicalWidth, (int32_t)logicalHeight
          );
          xdg_surface_ack_configure(xdg_surface, serial);
       },
   };
   xdg_surface_add_listener(xdg_surface_, &xdg_surf_listener, this);

   vk_surface_ = create_surface(display_.get(), surface_.get(), vk_instance_.instance());
}

void WaylandWindow::init_toplevel(const char *title) {
   xdg_toplevel_ = xdg_surface_get_toplevel(xdg_surface_);
   static constexpr xdg_toplevel_listener toplevel_listener = {
       .configure =
           [](void *user_data, struct xdg_toplevel *xdg_toplevel, int32_t width, int32_t height,
              struct wl_array *states) {
              // TODO: Check if width/height are zero. If so, autonomously set window size
              WaylandWindow *window = reinterpret_cast<WaylandWindow *>(user_data);
              window->width_ = width;
              window->height_ = height;
           },

       .close =
           [](void *user_ptr, struct xdg_toplevel *xdg_toplevel) {
              reinterpret_cast<WaylandWindow *>(user_ptr)->open_ = false;
           },

       .configure_bounds = [](void *user_ptr, struct xdg_toplevel *xdg_toplevel, int32_t width,
                              int32_t height) {},
       .wm_capabilities = [](void *user_ptr, struct xdg_toplevel *xdg_toplevel,
                             struct wl_array *capabilities) {},
   };

   xdg_toplevel_set_user_data(xdg_toplevel_, this);
   xdg_toplevel_add_listener(xdg_toplevel_, &toplevel_listener, this);
   xdg_toplevel_set_title(xdg_toplevel_, title);
}

void WaylandWindow::init_seat() {
   static constexpr wl_seat_listener seat_listener = {
       .capabilities =
           [](void *user_pointer, wl_seat *seat, uint32_t capabilities) {
              auto window = reinterpret_cast<WaylandWindow *>(user_pointer);

              if (capabilities & WL_SEAT_CAPABILITY_KEYBOARD) {
                 window->keyboard_ = wl_seat_get_keyboard(seat);
              }

              if (capabilities & WL_SEAT_CAPABILITY_POINTER) {
                 window->pointer_ = wl_seat_get_pointer(seat);
              }
           },
       .name = [](void *user_pointer, wl_seat *seat, const char *name) {},
   };
   wl_seat_add_listener(seat_, &seat_listener, this);
}

void WaylandWindow::init_keyboard() {
   static constexpr wl_keyboard_listener kb_listener = {
       .keymap =
           [](void *user_data, wl_keyboard *kb, uint32_t format, int32_t fd, uint32_t size) {
              auto window = reinterpret_cast<WaylandWindow *>(user_data);

              void *keymap_str = mmap(nullptr, size, PROT_READ, MAP_SHARED, fd, 0);

              xkb_keymap_unref(window->keymap_);
              window->keymap_ = xkb_keymap_new_from_string(
                  window->xkb_ctx_, reinterpret_cast<const char *>(keymap_str),
                  XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS
              );

              munmap(keymap_str, size);
              close(fd);
           },

       .enter =
           [](void *user_data, wl_keyboard *kb, uint32_t serial, wl_surface *surface,
              wl_array *keys) {
              auto window = reinterpret_cast<WaylandWindow *>(user_data);
              if (window->keymap_ == nullptr) {
                 return;
              }

              xkb_state_unref(window->xkb_state_);
              window->xkb_state_ = xkb_state_new(window->keymap_);
           },
       .leave =
           [](void *user_data, wl_keyboard *kb, uint32_t serial, wl_surface *surface) {
              auto window = reinterpret_cast<WaylandWindow *>(user_data);
              xkb_state_unref(window->xkb_state_);
              window->xkb_state_ = nullptr;
           },

       .key =
           [](void *user_data, wl_keyboard *kb, uint32_t serial, uint32_t time, uint32_t key,
              uint32_t state) {
              auto window = reinterpret_cast<WaylandWindow *>(user_data);
              if (window->xkb_state_ == nullptr) {
                 return;
              }

              uint32_t evdev_key = key + 8;
              bool pressed = state == WL_KEYBOARD_KEY_STATE_PRESSED;

              xkb_keysym_t keysym = xkb_state_key_get_one_sym(window->xkb_state_, evdev_key);
              uint8_t xi2_key = xkb_to_xinput2(keysym);
              window->pressed_keys_[xi2_key] = pressed;

              if (pressed) {
                 window->process_utf8_keyboard_input(evdev_key);
              }
           },

       .modifiers =
           [](void *user_data, wl_keyboard *kb, uint32_t serial, uint32_t mods_pressed,
              uint32_t mods_latched, uint32_t mods_locked, uint32_t group) {
              auto window = reinterpret_cast<WaylandWindow *>(user_data);
              if (window->xkb_state_ == nullptr) {
                 return;
              }

              xkb_state_update_mask(
                  window->xkb_state_, mods_pressed, mods_latched, mods_locked, 0, 0, group
              );
           },

       .repeat_info = [](void *user_data, wl_keyboard *kb, int32_t rate, int32_t delay) {},
   };

   wl_keyboard_add_listener(keyboard_, &kb_listener, this);
}

void WaylandWindow::init_pointer() {
   static constexpr wl_pointer_listener listener = {
       .enter =
           [](void *user_data, struct wl_pointer *wl_pointer, uint32_t serial,
              struct wl_surface *surface, wl_fixed_t surface_x, wl_fixed_t surface_y) {
              auto window = reinterpret_cast<WaylandWindow *>(user_data);
              if (window->mouse_captured_) {
                 wl_pointer_set_cursor(window->pointer_, serial, nullptr, 0, 0);
              }
           },

       .leave = [](void *data, struct wl_pointer *wl_pointer, uint32_t serial,
                   struct wl_surface *surface) {},
       .motion = [](void *data, struct wl_pointer *wl_pointer, uint32_t time, wl_fixed_t surface_x,
                    wl_fixed_t surface_y) {},
       .button = [](void *data, struct wl_pointer *wl_pointer, uint32_t serial, uint32_t time,
                    uint32_t button, uint32_t state) {},
       .axis = [](void *data, struct wl_pointer *wl_pointer, uint32_t time, uint32_t axis,
                  wl_fixed_t value) {},
       .frame = [](void *data, struct wl_pointer *wl_pointer) {},
       .axis_source = [](void *data, struct wl_pointer *wl_pointer, uint32_t axis_source) {},
       .axis_stop = [](void *data, struct wl_pointer *wl_pointer, uint32_t time, uint32_t axis) {},
       .axis_discrete = [](void *data, struct wl_pointer *wl_pointer, uint32_t axis,
                           int32_t discrete) {},
       .axis_value120 = [](void *data, struct wl_pointer *wl_pointer, uint32_t axis,
                           int32_t value120) {},
       .axis_relative_direction = [](void *data, struct wl_pointer *wl_pointer, uint32_t axis,
                                     uint32_t direction) {},
   };

   wl_pointer_add_listener(pointer_, &listener, this);
}

void WaylandWindow::init_relative_pointer() {
   relative_pointer_ =
       zwp_relative_pointer_manager_v1_get_relative_pointer(relative_pointer_manager_, pointer_);

   static constexpr zwp_relative_pointer_v1_listener listener = {
       .relative_motion = [](void *user_data,
                             struct zwp_relative_pointer_v1 *zwp_relative_pointer_v1,
                             uint32_t utime_hi, uint32_t utime_lo, wl_fixed_t dx, wl_fixed_t dy,
                             wl_fixed_t dx_unaccel, wl_fixed_t dy_unaccel) {
          auto *window = reinterpret_cast<WaylandWindow *>(user_data);
          window->delta_mouse_x_ += dx_unaccel / 256;
          window->delta_mouse_y_ -= dy_unaccel / 256;
       },
   };

   zwp_relative_pointer_v1_add_listener(relative_pointer_, &listener, this);
}

void WaylandWindow::init_fractional_scale() {
   fractional_scale_ = wp_fractional_scale_manager_v1_get_fractional_scale(
       fractional_scale_manager_, surface_.get()
   );

   static constexpr wp_fractional_scale_v1_listener listener = {
       .preferred_scale = [](void *user_data, struct wp_fractional_scale_v1 *wp_fractional_scale_v1,
                             uint32_t scale) {
          auto *window = reinterpret_cast<WaylandWindow *>(user_data);
          window->scale_ = (int32_t)scale;
       },
   };

   wp_fractional_scale_v1_add_listener(fractional_scale_, &listener, this);
}

void WaylandWindow::init_viewport() {
   viewport_ = wp_viewporter_get_viewport(viewporter_, surface_.get());
}

void WaylandWindow::init_locked_pointer() {
   static constexpr zwp_locked_pointer_v1_listener listener = {
       .locked = [](void *user_data, zwp_locked_pointer_v1 *locked_pointer) {},
       .unlocked = [](void *user_data, zwp_locked_pointer_v1 *locked_pointer) {},
   };
   zwp_locked_pointer_v1_add_listener(locked_pointer_, &listener, this);
}

void WaylandWindow::process_utf8_keyboard_input(uint32_t evdev_key) {
   int letter_size = xkb_state_key_get_utf8(
       xkb_state_, evdev_key, &typed_letters_[next_typed_letter_],
       sizeof(typed_letters_) - next_typed_letter_
   );

   next_typed_letter_ =
       std::min(sizeof(typed_letters_), static_cast<size_t>(next_typed_letter_ + letter_size));
}
