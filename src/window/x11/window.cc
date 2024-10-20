#include "window.h"

#include <stdexcept>

#include <X11/Xlib.h>
#include <X11/extensions/XInput2.h>
#define VK_USE_PLATFORM_XLIB_XHR
#include <vulkan/vulkan_xlib.h>

#include "gpu/instance.h"
#include "gpu/status.h"

using namespace vkad;

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

} // namespace

vkad::Window::Window(const Instance &vk_instance, const char *title)
    : width_(1280), height_(720), delta_mouse_x_(0), delta_mouse_y_(0) {
   Display *display = XOpenDisplay(NULL);
   display_ = display;
   if (display_ == nullptr) {
      throw std::runtime_error("XOpenDisplay returned null");
   }

   xi_opcode_ = ensure_xinput2(display);

   ::Window root = DefaultRootWindow(display);

   window_ = XCreateSimpleWindow(
       display, root, 0, 0, width_, height_, 1, BlackPixel(display, 0), BlackPixel(display, 0)
   );

   XMapWindow(display, window_);
   XFlush(display);

   wm_delete_window_ = XInternAtom(display, "WM_DELETE_WINDOW", false);
   XSetWMProtocols(display, window_, &wm_delete_window_, 1);

   XSelectInput(display, window_, StructureNotifyMask);

   unsigned char mask[XIMaskLen(XI_RawMotion)] = {0};
   XIEventMask event_mask = {
       .deviceid = XIAllDevices,
       .mask_len = sizeof(mask),
       .mask = mask,
   };
   XISetMask(mask, XI_RawMotion);
   XISelectEvents(display, DefaultRootWindow(display), &event_mask, 1);

   surface_ = create_surface(display, window_, vk_instance.handle());
}

vkad::Window::~Window() {
   XDestroyWindow(reinterpret_cast<Display *>(display_), window_);
   XCloseDisplay(reinterpret_cast<Display *>(display_));
}

bool vkad::Window::poll() {
   delta_mouse_x_ = 0;
   delta_mouse_y_ = 0;
   auto display = reinterpret_cast<Display *>(display_);

   while (true) {
      if (XPending(display) < 1) {
         break;
      }

      XEvent event;
      XNextEvent(display, &event);

      switch (event.type) {
      case ConfigureNotify:
         width_ = event.xconfigure.width;
         height_ = event.xconfigure.height;
         break;

      case ClientMessage:
         if (event.xclient.data.l[0] == wm_delete_window_) {
            return false;
         }

      case GenericEvent:
         process_generic_event(event);
      }
   }

   if (mouse_captured_) {
      XWarpPointer(display, window_, window_, 0, 0, 0, 0, width_ / 2, height_ / 2);
   }

   return true;
}

void vkad::Window::request_close() {}

void vkad::Window::process_generic_event(XEvent &event) {
   if (event.xcookie.extension != xi_opcode_ || event.xcookie.evtype != XI_RawMotion) {
      return;
   }

   auto display = reinterpret_cast<Display *>(display_);
   if (!XGetEventData(display, &event.xcookie)) {
      return;
   }

   XIRawEvent *raw_event = reinterpret_cast<XIRawEvent *>(event.xcookie.data);
   delta_mouse_x_ += static_cast<int>(raw_event->raw_values[0]);
   delta_mouse_y_ += static_cast<int>(raw_event->raw_values[1]);
   XFreeEventData(display, &event.xcookie);
}
