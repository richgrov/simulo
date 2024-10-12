#ifndef VKAD_WINDOW_X11_WINDOW_H_
#define VKAD_WINDOW_X11_WINDOW_H_

#include <string_view>

#include "gpu/instance.h"

namespace vkad {

class Window {
public:
   static inline std::vector<const char *> vulkan_extensions() {
      return {"VK_KHR_surface", "VK_KHR_xlib_surface"};
   }

   explicit Window(const Instance &vk_instance, const char *title);
   ~Window();

   bool poll();

   void set_capture_mouse(bool capture);

   void request_close();

   inline VkSurfaceKHR surface() const {
      return nullptr;
   }

   int width() const {
      return 0;
   }

   int height() const {
      return 0;
   }

   int mouse_x() const {
      return 0;
   }

   int mouse_y() const {
      return 0;
   }

   int delta_mouse_x() const {
      return 0;
   }

   int delta_mouse_y() const {
      return 0;
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
   void *display_;
   unsigned long window_;
};

} // namespace vkad

#endif // !VKAD_WINDOW_X11_WINDOW_H_
