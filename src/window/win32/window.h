#ifndef VKAD_WINDOW_WIN32_WINDOW_H_
#define VKAD_WINDOW_WIN32_WINDOW_H_

#include <memory>
#include <string_view>
#include <vector>

#include <Windows.h>
#include <vulkan/vulkan_core.h>

#include "gpu/instance.h"
#include "util/bitfield.h"

namespace vkad {

LRESULT CALLBACK window_proc(HWND window, UINT msg, WPARAM w_param, LPARAM l_param);

class Window {
public:
   static inline std::vector<const char *> vulkan_extensions() {
      return {"VK_KHR_surface", "VK_KHR_win32_surface"};
   }

   explicit Window(const Instance &vk_instance, const char *title);
   ~Window();

   bool poll();

   void set_capture_mouse(bool capture);

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
      return mouse_x_;
   }

   int mouse_y() const {
      return mouse_y_;
   }

   int delta_mouse_x() const {
      return delta_mouse_x_;
   }

   int delta_mouse_y() const {
      return delta_mouse_y_;
   }

   bool left_clicking() const {
      return left_clicking_;
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
   const Instance &vk_instance_;
   HWND window_;
   bool open_;
   bool closing_;
   bool cursor_captured_;
   WORD window_x_;
   WORD window_y_;
   WORD width_;
   WORD height_;
   VkSurfaceKHR surface_;

   int mouse_x_;
   int mouse_y_;
   int delta_mouse_x_;
   int delta_mouse_y_;
   bool left_clicking_;

   Bitfield<256> pressed_keys_;
   Bitfield<256> prev_pressed_keys_;

   char typed_chars_[64];
   int next_typed_letter_;

   friend LRESULT CALLBACK window_proc(HWND window, UINT msg, WPARAM w_param, LPARAM l_param);
};

inline std::unique_ptr<Window> create_window(const Instance &vk_instance, const char *title) {
   return std::make_unique<Window>(vk_instance, title);
}

}; // namespace vkad

#endif // !VKAD_WINDOW_WIN32_WINDOW_H_
