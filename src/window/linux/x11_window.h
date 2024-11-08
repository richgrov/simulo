#ifndef VKAD_WINDOW_X11_WINDOW_H_
#define VKAD_WINDOW_X11_WINDOW_H_

#include <bitset>
#include <string_view>

#include <vulkan/vulkan_core.h>

#include "gpu/instance.h"
#include "window.h"

union _XEvent;
struct _XDisplay;
struct _XIC;
#define XLIB_NUM_KEYS (255 - 8)

namespace vkad {

class X11Window : public vkad::Window {
public:
   static inline std::vector<const char *> vulkan_extensions() {
      return {"VK_KHR_surface", "VK_KHR_xlib_surface"};
   }

   explicit X11Window(const Instance &vk_instance, const char *title);
   ~X11Window();

   virtual bool poll() override;

   virtual void set_capture_mouse(bool capture) override;

   virtual void request_close() override;

   virtual inline VkSurfaceKHR surface() const override {
      return surface_;
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
      return std::string_view(typed_chars_, next_typed_letter_);
   }

private:
   void process_generic_event(_XEvent &event);
   void process_char_input(_XEvent &event);

   _XDisplay *display_;
   int xi_opcode_;
   _XIC *input_ctx_;
   unsigned long window_;
   unsigned long wm_delete_window_;
   bool mouse_captured_;
   VkSurfaceKHR surface_;
   int width_;
   int height_;
   int delta_mouse_x_;
   int delta_mouse_y_;
   std::bitset<XLIB_NUM_KEYS> pressed_keys_;
   std::bitset<XLIB_NUM_KEYS> prev_pressed_keys_;
   char typed_chars_[64];
   int next_typed_letter_;
   unsigned long invisible_cursor_;
};

} // namespace vkad

#endif // !VKAD_WINDOW_X11_WINDOW_H_
