#pragma once

#include <cstdint>
#include <string_view>

#define VK_USE_PLATFORM_METAL_EXT
#include <vulkan/vulkan.h>

#ifdef __OBJC__
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
@class WindowDelegate;
@class WindowView;
#endif

#include "gpu/gpu.h"
#include "util/bitfield.h"

namespace simulo {

class Window {
public:
   explicit Window(const Gpu &gpu, const char *title);
   ~Window();

   inline VkSurfaceKHR surface() {
      VkMetalSurfaceCreateInfoEXT create_info = {};
      create_info.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;

      VkSurfaceKHR surface = {};
      vkCreateMetalSurfaceEXT(instance_, &create_info, nullptr, &surface);
      return surface;
   }

   bool poll();

   void set_capture_mouse(bool capture);

   void request_close();

   int width() const;

   int height() const;

   int mouse_x() const;

   int mouse_y() const;

   int delta_mouse_x() const;

   int delta_mouse_y() const;

   bool left_clicking() const;

   bool is_key_down(uint8_t key_code) const;

   bool key_just_pressed(uint8_t key_code) const;

   std::string_view typed_chars() const;

#ifdef __OBJC__
   MTLPixelFormat layer_pixel_format() const {
      return layer_pixel_format_;
   }

   CAMetalLayer *metal_layer() const {
      return metal_layer_;
   }
#else
   void *layer_pixel_format() const {
      return layer_pixel_format_;
   }

   void *metal_layer() const {
      return metal_layer_;
   }
#endif

private:
#ifdef __OBJC__
   NSWindow *ns_window_;
   MTLPixelFormat layer_pixel_format_;
   CAMetalLayer *metal_layer_;
   WindowDelegate *window_delegate_;
   WindowView *window_view_;
#else
   void *ns_window_;
   void *layer_pixel_format_;
   void *metal_layer_;
   void *window_delegate_;
   void *window_view_;
#endif

   bool closing_ = false;
   bool cursor_captured_ = false;
   VkInstance instance_;
};

inline std::unique_ptr<Window> create_window(const Gpu &gpu, const char *title) {
   return std::make_unique<Window>(gpu, title);
}

} // namespace simulo
