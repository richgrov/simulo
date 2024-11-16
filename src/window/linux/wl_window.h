#ifndef VKAD_WINDOW_LINUX_WL_WINDOW_H_
#define VKAD_WINDOW_LINUX_WL_WINDOW_H_

#include "gpu/instance.h"
#include "window/linux/window.h"

struct wl_display;
struct wl_registry;
struct wl_compositor;
struct wl_surface;
struct xdg_wm_base;
struct xdg_surface;
struct xdg_toplevel;
struct wl_seat;
struct wl_keyboard;

struct xkb_context;
struct xkb_keymap;

namespace vkad {

class WaylandWindow : public Window {
public:
   WaylandWindow(const Instance &vk_instance, const char *title);

   ~WaylandWindow();

   virtual bool poll() override;

   virtual void set_capture_mouse(bool capture) override {}

   virtual void request_close() override {}

   virtual inline VkSurfaceKHR surface() const override {
      return vk_surface_;
   }

   virtual int width() const override {
      return width_;
   }

   virtual int height() const override {
      return height_;
   }

   virtual int mouse_x() const override {
      return 0;
   }

   virtual int mouse_y() const override {
      return 0;
   }

   virtual int delta_mouse_x() const override {
      return 0;
   }

   virtual int delta_mouse_y() const override {
      return 0;
   }

   virtual bool left_clicking() const override {
      return false;
   }

   virtual bool is_key_down(uint8_t key_code) const override {
      return false;
   }

   virtual bool key_just_pressed(uint8_t key_code) const override {
      return false;
   }

   virtual std::string_view typed_chars() const override {
      return "";
   }

private:

   static void
   kb_handler_keymap(void *user_data, wl_keyboard *kb, uint32_t format, int32_t fd, uint32_t size);

   void init_registry();
   void init_xdg_wm_base();

   static void toplevel_configure(
       void *user_data, struct xdg_toplevel *xdg_toplevel, int32_t width, int32_t height,
       struct wl_array *states
   );

   static void toplevel_close(void *data, struct xdg_toplevel *xdg_toplevel);

   static void toplevel_configure_bounds(
       void *data, struct xdg_toplevel *xdg_toplevel, int32_t width, int32_t height
   );

   static void toplevel_wm_capabilities(
       void *data, struct xdg_toplevel *xdg_toplevel, struct wl_array *capabilities
   );

   const Instance &vk_instance_;
   wl_display *display_ = nullptr;
   wl_registry *registry_ = nullptr;
   wl_compositor *compositor_ = nullptr;
   wl_surface *surface_ = nullptr;
   VkSurfaceKHR vk_surface_ = nullptr;
   xdg_wm_base *xdg_base_ = nullptr;
   xdg_surface *xdg_surface_ = nullptr;
   xdg_toplevel *xdg_toplevel_ = nullptr;
   wl_seat *seat_ = nullptr;
   wl_keyboard *keyboard_ = nullptr;

   xkb_context *xkb_ctx_ = nullptr;
   xkb_keymap *keymap_ = nullptr;

   int width_ = 0;
   int height_ = 0;
   bool open_ = true;
};

} // namespace vkad

#endif // !VKAD_WINDOW_LINUX_WL_WINDOW_H_
