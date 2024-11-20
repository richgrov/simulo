#ifndef VKAD_WINDOW_LINUX_WL_WINDOW_H_
#define VKAD_WINDOW_LINUX_WL_WINDOW_H_

#include "gpu/instance.h"
#include "window/linux/window.h"
#include <bitset>
#include <string_view>

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

struct xkb_context;
struct xkb_state;
struct xkb_keymap;
struct zwp_relative_pointer_manager_v1;
struct zwp_relative_pointer_v1;

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
      return delta_mouse_x_;
   }

   virtual int delta_mouse_y() const override {
      return delta_mouse_y_;
   }

   virtual bool left_clicking() const override {
      return false;
   }

   virtual bool is_key_down(uint8_t key_code) const override {
      return pressed_keys_[key_code];
   }

   virtual bool key_just_pressed(uint8_t key_code) const override {
      return !prev_pressed_keys_[key_code] && pressed_keys_[key_code];
   }

   virtual std::string_view typed_chars() const override {
      return std::string_view(typed_letters_, next_typed_letter_);
   }

private:
   void init_registry();
   void init_xdg_wm_base();
   void init_surfaces();
   void init_toplevel(const char *title);

   void init_seat();
   void init_keyboard();
   void init_relative_pointer();

   void process_utf8_keyboard_input(uint32_t evdev_key);

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
   xkb_state *xkb_state_ = nullptr;
   xkb_keymap *keymap_ = nullptr;

   wl_pointer *pointer_ = nullptr;
   zwp_relative_pointer_manager_v1 *relative_pointer_manager_ = nullptr;
   zwp_relative_pointer_v1 *relative_pointer_ = nullptr;

   int width_ = 0;
   int height_ = 0;
   bool open_ = true;
   std::bitset<256> pressed_keys_;
   std::bitset<256> prev_pressed_keys_;
   char typed_letters_[64];
   int next_typed_letter_ = 0;
   int delta_mouse_x_ = 0;
   int delta_mouse_y_ = 0;
};

} // namespace vkad

#endif // !VKAD_WINDOW_LINUX_WL_WINDOW_H_
