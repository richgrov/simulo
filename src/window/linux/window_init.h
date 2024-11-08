#ifndef VKAD_WINDOW_LINUX_WINDOW_INIT_H_
#define VKAD_WINDOW_LINUX_WINDOW_INIT_H_

#include <memory>

#include "window/linux/x11_window.h"

namespace vkad {

inline std::unique_ptr<Window> create_window(const Instance &vk_instance, const char *title) {
   return std::make_unique<X11Window>(vk_instance, title);
}

} // namespace vkad

#endif // !VKAD_WINDOW_LINUX_WINDOW_INIT_H_
