#include "x11_window.h"

#include <cstring>
#include <stdexcept>

#include <X11/Xlib.h>
#include <X11/extensions/XInput2.h>
#define VK_USE_PLATFORM_XLIB_XHR
#include <vulkan/vulkan_xlib.h>

#include "gpu/vulkan/gpu.h"
#include "gpu/vulkan/status.h"

using namespace simulo;

namespace {

int ensure_xinput2(Display *display) {
   int xi_opcode, event_unused, error_unused;
   if (!XQueryExtension(display, "XInputExtension", &xi_opcode, &event_unused, &error_unused)) {
      throw std::runtime_error("XInput not available");
   }

   int major = 2;
   int minor = 0;
   if (XIQueryVersion(display, &major, &minor) != Success) {
      throw std::runtime_error("XInput version 2 not supported");
   }

   return xi_opcode;
}

VkSurfaceKHR create_surface(Display *display, ::Window window, VkInstance instance) {
   VkXlibSurfaceCreateInfoKHR surface_create = {
       .sType = VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR,
       .dpy = display,
       .window = window,
   };

   VkSurfaceKHR surface;
   VKAD_VK(vkCreateXlibSurfaceKHR(instance, &surface_create, nullptr, &surface));
   return surface;
}

XIC create_input_context(Display *display, ::Window window) {
   XIM input_method = XOpenIM(display, nullptr, nullptr, nullptr);
   if (input_method == nullptr) {
      throw std::runtime_error("failed to open input method");
   }

   XIC input_ctx = XCreateIC(
       input_method, XNInputStyle, XIMPreeditNothing | XIMStatusNothing, XNClientWindow, window,
       nullptr
   );
   if (input_ctx == nullptr) {
      throw std::runtime_error("failed to create input context");
   }

   return input_ctx;
}

void listen_raw_mouse_motion_events(Display *display) {
   unsigned char mask[XIMaskLen(XI_RawMotion)] = {0};
   XIEventMask event_mask = {
       .deviceid = XIAllDevices,
       .mask_len = sizeof(mask),
       .mask = mask,
   };
   XISetMask(mask, XI_RawMotion);
   XISelectEvents(display, DefaultRootWindow(display), &event_mask, 1);
}

Cursor create_invisible_cursor(Display *display, ::Window window) {
   char bitmap_data = 0;
   Pixmap empty_img = XCreateBitmapFromData(display, window, &bitmap_data, 1, 1);
   XColor black;
   XAllocNamedColor(
       display, DefaultColormap(display, DefaultScreen(display)), "black", &black, &black
   );
   return XCreatePixmapCursor(display, empty_img, empty_img, &black, &black, 0, 0);
}

} // namespace

simulo::X11Window::X11Window(const Gpu &vk_instance, const char *title)
    : vk_instance_(vk_instance),
      mouse_captured_(false),
      width_(1280),
      height_(720),
      delta_mouse_x_(0),
      delta_mouse_y_(0),
      typed_chars_{},
      next_typed_letter_(0) {
   display_ = XOpenDisplay(NULL);
   if (display_ == nullptr) {
      throw std::runtime_error("XOpenDisplay returned null");
   }

   xi_opcode_ = ensure_xinput2(display_);

   window_ = XCreateSimpleWindow(
       display_,                    //
       DefaultRootWindow(display_), //
       0,                           // x
       0,                           // y
       width_,                      //
       height_,                     //
       1,                           // border width
       BlackPixel(display_, 0),     // border color
       BlackPixel(display_, 0)      // background color
   );

   XMapWindow(display_, window_);
   XFlush(display_);

   wm_delete_window_ = XInternAtom(display_, "WM_DELETE_WINDOW", false);
   XSetWMProtocols(display_, window_, &wm_delete_window_, 1);
   XSelectInput(display_, window_, StructureNotifyMask | KeyPressMask | KeyReleaseMask);

   input_ctx_ = create_input_context(display_, window_);
   XSetICFocus(input_ctx_);
   listen_raw_mouse_motion_events(display_);

   invisible_cursor_ = create_invisible_cursor(display_, window_);

   surface_ = create_surface(display_, window_, vk_instance.instance());

   // Manually query if size changed because ConfigureNotify is not guaranteed to be received on
   // startup.
   XWindowAttributes attrs;
   XGetWindowAttributes(display_, window_, &attrs);
   width_ = attrs.width;
   height_ = attrs.height;
}

simulo::X11Window::~X11Window() {
   XFreeCursor(display_, invisible_cursor_);
   vkDestroySurfaceKHR(vk_instance_.instance(), surface_, nullptr);
   XDestroyWindow(display_, window_);
   XCloseDisplay(display_);
}

bool simulo::X11Window::poll() {
   prev_pressed_keys_ = pressed_keys_;
   std::memset(typed_chars_, 0, sizeof(typed_chars_));
   next_typed_letter_ = 0;

   delta_mouse_x_ = 0;
   delta_mouse_y_ = 0;

   while (XPending(display_) > 0) {
      XEvent event;
      XNextEvent(display_, &event);

      switch (event.type) {
      case ConfigureNotify:
         width_ = event.xconfigure.width;
         height_ = event.xconfigure.height;
         break;

      case ClientMessage:
         if (event.xclient.data.l[0] == wm_delete_window_) {
            return false;
         }
         break;

      case KeyPress:
         process_char_input(event);
         pressed_keys_[static_cast<unsigned char>(event.xkey.keycode)] = true;
         break;

      case KeyRelease:
         pressed_keys_[static_cast<unsigned char>(event.xkey.keycode)] = false;
         break;

      case GenericEvent:
         process_generic_event(event);
         break;
      }
   }

   if (mouse_captured_) {
      XWarpPointer(display_, window_, window_, 0, 0, 0, 0, width_ / 2, height_ / 2);
   }

   return true;
}

void simulo::X11Window::set_capture_mouse(bool capture) {
   mouse_captured_ = capture;
   XDefineCursor(display_, window_, capture ? invisible_cursor_ : None);
}

void simulo::X11Window::request_close() {}

void simulo::X11Window::process_generic_event(XEvent &event) {
   if (event.xcookie.extension != xi_opcode_ || event.xcookie.evtype != XI_RawMotion) {
      return;
   }

   if (!XGetEventData(display_, &event.xcookie)) {
      return;
   }

   XIRawEvent *raw_event = reinterpret_cast<XIRawEvent *>(event.xcookie.data);
   delta_mouse_x_ += static_cast<int>(raw_event->raw_values[0]);
   delta_mouse_y_ -= static_cast<int>(raw_event->raw_values[1]);
   XFreeEventData(display_, &event.xcookie);
}

void simulo::X11Window::process_char_input(_XEvent &event) {
   KeySym keysym_unused;
   Status status_unused;
   int len = Xutf8LookupString(
       input_ctx_, &event.xkey, typed_chars_ + next_typed_letter_,
       sizeof(typed_chars_) - next_typed_letter_, &keysym_unused, &status_unused
   );
   next_typed_letter_ += len;
}
