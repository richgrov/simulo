#ifndef VKAD_WINDOW_X11_WINDOW_H_
#define VKAD_WINDOW_X11_WINDOW_H_

#include <bitset>
#include <string_view>

#include <vulkan/vulkan_core.h>

#include "gpu/instance.h"

union _XEvent;
struct _XDisplay;
struct _XIC;
#define XLIB_NUM_KEYS (255 - 8)

namespace vkad {

class Window {
public:
   static inline std::vector<const char *> vulkan_extensions() {
      return {"VK_KHR_surface", "VK_KHR_xlib_surface"};
   }

   explicit Window(const Instance &vk_instance, const char *title);
   ~Window();

   bool poll();

   void set_capture_mouse(bool capture) {
      mouse_captured_ = capture;
   }

   void request_close();

   inline VkSurfaceKHR surface() const {
      return surface_;
   }

   int width() const {
      return width_;
   }

   int height() const {
      return height_;
   }

   int mouse_x() const {
      return 0;
   }

   int mouse_y() const {
      return 0;
   }

   int delta_mouse_x() const {
      return delta_mouse_x_;
   }

   int delta_mouse_y() const {
      return delta_mouse_y_;
   }

   bool left_clicking() const {
      return false;
   }

   inline bool is_key_down(uint8_t key_code) const {
      return pressed_keys_[key_code];
   }

   inline bool key_just_pressed(uint8_t key_code) const {
      return !prev_pressed_keys_[key_code] && pressed_keys_[key_code];
   }

   std::string_view typed_chars() const {
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
};

} // namespace vkad

#endif // !VKAD_WINDOW_X11_WINDOW_H_
