#pragma once

#include <cstdint>
#include <string_view>

#ifdef __OBJC__
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
@class WindowDelegate;
@class WindowView;
#endif

#include "gpu/gpu.h"
#include "util/bitfield.h"

namespace vkad {

class Window {
public:
   explicit Window(const Gpu &gpu, const char *title);
   ~Window();

   bool poll();

   void set_capture_mouse(bool capture);

   void request_close();

   int width() const;

   int height() const;

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

   bool is_key_down(uint8_t key_code) const;

   bool key_just_pressed(uint8_t key_code) const;

   std::string_view typed_chars() const {
      return std::string_view(typed_chars_, next_typed_letter_);
   }

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

   int mouse_x_;
   int mouse_y_;
   int delta_mouse_x_;
   int delta_mouse_y_;
   bool left_clicking_;


   char typed_chars_[64];
   int next_typed_letter_;
};

inline std::unique_ptr<Window> create_window(const Gpu &gpu, const char *title) {
   return std::make_unique<Window>(gpu, title);
}

} // namespace vkad
