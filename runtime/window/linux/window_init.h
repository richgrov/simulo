#pragma once

#include <memory>

#include "gpu/gpu.h"
#include "window/linux/wl_window.h"  // IWYU pragma: export
#include "window/linux/x11_window.h" // IWYU pragma: export

namespace simulo {

inline std::unique_ptr<Window> create_window(const Gpu &vk_instance, const char *title) {
   if (Window::running_on_wayland()) {
      return std::make_unique<WaylandWindow>(vk_instance, title);
   }

   return std::make_unique<X11Window>(vk_instance, title);
}

} // namespace simulo
