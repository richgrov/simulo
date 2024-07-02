#ifndef VILLA_WINDOW_WIN32_WINDOW_H_
#define VILLA_WINDOW_WIN32_WINDOW_H_

#include <vector>

#include <Windows.h>
#include <vulkan/vulkan_core.h>

namespace villa {

class Window {
public:
   explicit Window(const char *title);

   bool poll();

   inline void close__internal() {
      open_ = false;
   }

   inline std::vector<const char *> vulkan_extensions() const {
      return {"VK_KHR_surface", "VK_KHR_win32_surface"};
   }

   VkSurfaceKHR create_surface(VkInstance instance);

   inline void set_size__internal(WORD width, WORD height) {
      width_ = width;
      height_ = height;
   }

   int width() const {
      return width_;
   }

   int height() const {
      return height_;
   }

   inline void set_mouse__internal(int mouse_x, int mouse_y) {
      mouse_x_ = mouse_x;
      mouse_y_ = mouse_y;
   }

   int mouse_x() const {
      return mouse_x_;
   }

   int mouse_y() const {
      return mouse_y_;
   }

private:
   HWND window_;
   bool open_;
   WORD width_;
   WORD height_;

   int mouse_x_;
   int mouse_y_;
};

}; // namespace villa

#endif // !VILLA_WINDOW_WIN32_WINDOW_H_
