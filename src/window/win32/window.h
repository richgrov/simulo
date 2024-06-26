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

private:
   HWND window_;
   bool open_;
};

}; // namespace villa

#endif // !VILLA_WINDOW_WIN32_WINDOW_H_
