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
   display_ = XOpenDisplay(NULL);
   if (display_ == nullptr) {
      throw std::runtime_error("XOpenDisplay returned null");
   }

   xi_opcode_ = ensure_xinput2(display_);

   ::Window root = DefaultRootWindow(display_);

   window_ = XCreateSimpleWindow(
       display_, root, 0, 0, width_, height_, 1, BlackPixel(display_, 0), BlackPixel(display_, 0)
   );

   XMapWindow(display_, window_);
   XFlush(display_);

   wm_delete_window_ = XInternAtom(display_, "WM_DELETE_WINDOW", false);
   XSetWMProtocols(display_, window_, &wm_delete_window_, 1);

   XSelectInput(display_, window_, StructureNotifyMask);

   unsigned char mask[XIMaskLen(XI_RawMotion)] = {0};
   XIEventMask event_mask = {
       .deviceid = XIAllDevices,
       .mask_len = sizeof(mask),
       .mask = mask,
   };
   XISetMask(mask, XI_RawMotion);
   XISelectEvents(display_, DefaultRootWindow(display_), &event_mask, 1);

   surface_ = create_surface(display_, window_, vk_instance.handle());
}

vkad::Window::~Window() {
   XDestroyWindow(display_, window_);
   XCloseDisplay(display_);
}

bool vkad::Window::poll() {
   delta_mouse_x_ = 0;
   delta_mouse_y_ = 0;

   while (true) {
      if (XPending(display_) < 1) {
         break;
      }

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

      case GenericEvent:
         process_generic_event(event);
      }
   }

   if (mouse_captured_) {
      XWarpPointer(display_, window_, window_, 0, 0, 0, 0, width_ / 2, height_ / 2);
   }

   return true;
}

void vkad::Window::request_close() {}

void vkad::Window::process_generic_event(XEvent &event) {
   if (event.xcookie.extension != xi_opcode_ || event.xcookie.evtype != XI_RawMotion) {
      return;
   }

   if (!XGetEventData(display_, &event.xcookie)) {
      return;
   }

   XIRawEvent *raw_event = reinterpret_cast<XIRawEvent *>(event.xcookie.data);
   delta_mouse_x_ += static_cast<int>(raw_event->raw_values[0]);
   delta_mouse_y_ += static_cast<int>(raw_event->raw_values[1]);
   XFreeEventData(display_, &event.xcookie);
}
