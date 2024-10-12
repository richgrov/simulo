#include "window.h"

#include <stdexcept>

#include <X11/Xlib.h>

#include "gpu/instance.h"

using namespace vkad;

vkad::Window::Window(const Instance &vk_instance, const char *title) {
   Display *display = XOpenDisplay(NULL);
   display_ = display;
   if (display_ == nullptr) {
      throw std::runtime_error("XOpenDisplay returned null");
   }

   ::Window root = DefaultRootWindow(display);

   window_ = XCreateSimpleWindow(
       display, root, 0, 0, 1280, 720, 1, BlackPixel(display, 0), BlackPixel(display, 0)
   );
   XMapWindow(display, window_);
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
   }

   return false;
}

void vkad::Window::set_capture_mouse(bool capture) {}

void vkad::Window::request_close() {}
