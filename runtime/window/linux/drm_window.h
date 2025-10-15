#pragma once

#include <string_view>

#include <vulkan/vulkan_core.h>

#include "gpu/vulkan/gpu.h"

namespace simulo {

class Window {
public:
   Window(const Gpu &vk_instance, const char *display_name);

   ~Window();

   bool poll() { return true; }

   void set_capture_mouse(bool capture) {} // not supported

   void request_close() {}

   inline VkSurfaceKHR surface() const { return surface_; }

   inline int width() const { return width_; }

   inline int height() const { return height_; }

   int mouse_x() const { return 0; } // not supported

   int mouse_y() const { return 0; } // not supported

   int delta_mouse_x() const { return 0; } // not supported

   int delta_mouse_y() const { return 0; } // not supported

   bool left_clicking() const { return false; } // not supported

   bool is_key_down(uint8_t key_code) const { return false; } // not supported

   bool key_just_pressed(uint8_t key_code) const { return false; } // not supported

   std::string_view typed_chars() const { return std::string_view(); } // not supported

private:
    VkInstance vk_instance_;
    VkDisplayKHR display_;
    int width_;
    int height_;
    VkSurfaceKHR surface_;
};

inline std::unique_ptr<Window> create_window(const Gpu &vk_instance, const char *title) {
    return std::make_unique<Window>(vk_instance, title);
}


} // namespace simulo