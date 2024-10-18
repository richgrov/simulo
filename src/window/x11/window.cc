#include "window.h"

#include <stdexcept>

#include <X11/Xlib.h>
#include <vulkan/vulkan_xlib.h>

#include "gpu/instance.h"
#include "gpu/status.h"

using namespace vkad;

namespace {

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

vkad::Window::Window(const Instance &vk_instance, const char *title) : width_(1280), height_(720) {
   Display *display = XOpenDisplay(NULL);
   display_ = display;
   if (display_ == nullptr) {
      throw std::runtime_error("XOpenDisplay returned null");
   }

   ::Window root = DefaultRootWindow(display);

   window_ = XCreateSimpleWindow(
       display, root, 0, 0, width_, height_, 1, BlackPixel(display, 0), BlackPixel(display, 0)
   );

   XMapWindow(display, window_);
   XFlush(display);

   wm_delete_window_ = XInternAtom(display, "WM_DELETE_WINDOW", false);
   XSetWMProtocols(display, window_, &wm_delete_window_, 1);

   XSelectInput(display, window_, StructureNotifyMask);

   surface_ = create_surface(display, window_, vk_instance.handle());
}

vkad::Window::~Window() {
   XDestroyWindow(reinterpret_cast<Display *>(display_), window_);
   XCloseDisplay(reinterpret_cast<Display *>(display_));
}

bool vkad::Window::poll() {
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
      }
   }

   if (mouse_captured_) {
      XWarpPointer(display, window_, window_, 0, 0, 0, 0, width_ / 2, height_ / 2);
   }

   return true;
}

void vkad::Window::request_close() {}
