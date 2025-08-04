#pragma once

struct wl_display;
struct wl_registry;
struct wl_compositor;
struct wl_surface;
struct xdg_wm_base;
struct xdg_surface;
struct xdg_toplevel;
struct wl_seat;
struct wl_keyboard;
struct wl_pointer;
struct wl_region;

struct xkb_context;
struct xkb_state;
struct xkb_keymap;
struct zwp_relative_pointer_manager_v1;
struct zwp_relative_pointer_v1;
struct wp_fractional_scale_manager_v1;
struct wp_fractional_scale_v1;
struct zwp_locked_pointer_v1;
struct zwp_pointer_constraints_v1;

namespace simulo {

class WaylandDeleter {
public:
   void operator()(wl_display *);
   void operator()(wl_registry *);
   void operator()(wl_compositor *);
   void operator()(wl_surface *);
};

} // namespace simulo
