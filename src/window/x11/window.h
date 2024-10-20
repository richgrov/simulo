#ifndef VKAD_WINDOW_X11_WINDOW_H_
#define VKAD_WINDOW_X11_WINDOW_H_

#include <string_view>

#include <vulkan/vulkan_core.h>

#include "gpu/instance.h"

union _XEvent;

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
      return false;
   }

   inline bool key_just_pressed(uint8_t key_code) const {
      return false;
   }

   std::string_view typed_chars() const {
      return "";
   }

private:
   void process_generic_event(_XEvent &event);

   void *display_;
   int xi_opcode_;
   unsigned long window_;
   unsigned long wm_delete_window_;
   bool mouse_captured_;
   VkSurfaceKHR surface_;
   int width_;
   int height_;
   int delta_mouse_x_;
   int delta_mouse_y_;
};

} // namespace vkad

#endif // !VKAD_WINDOW_X11_WINDOW_H_
