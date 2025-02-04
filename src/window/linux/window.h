#pragma once

#include <cstdlib>
#include <cstring>
#include <string_view>
#include <vector>
#include <vulkan/vulkan_core.h>

namespace vkad {

class Window {
public:
   static inline bool running_on_wayland() {
      const char *xdg_session_type = std::getenv("XDG_SESSION_TYPE");
      return xdg_session_type != nullptr && std::strcmp(xdg_session_type, "wayland") == 0;
   }

   static inline std::vector<const char *> vulkan_extensions() {
      if (running_on_wayland()) {
         return {"VK_KHR_surface", "VK_KHR_wayland_surface"};
      }

      return {"VK_KHR_surface", "VK_KHR_xlib_surface"};
   }

   virtual ~Window() {}

   virtual bool poll() = 0;

   virtual void set_capture_mouse(bool capture) = 0;

   virtual void request_close() = 0;

   virtual VkSurfaceKHR surface() const = 0;

   virtual int width() const = 0;

   virtual int height() const = 0;

   virtual int mouse_x() const = 0;

   virtual int mouse_y() const = 0;

   virtual int delta_mouse_x() const = 0;

   virtual int delta_mouse_y() const = 0;

   virtual bool left_clicking() const = 0;

   virtual bool is_key_down(uint8_t key_code) const = 0;

   virtual bool key_just_pressed(uint8_t key_code) const = 0;

   virtual std::string_view typed_chars() const = 0;
};

} // namespace vkad
