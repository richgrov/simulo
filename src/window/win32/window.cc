#include "window.h"

#include <Windows.h>
#include <format>
#include <stdexcept>

#include "vulkan/vulkan_core.h"
#define VK_USE_PLATFORM_WIN32_KHR
#include <vulkan/vulkan_win32.h>

using namespace villa;

namespace {

const char *WIN32_CLASS_NAME = "villa";

LRESULT CALLBACK window_proc(HWND window, UINT msg, WPARAM w_param, LPARAM l_param) {
   if (msg == WM_DESTROY) {
      LONG_PTR user_ptr = GetWindowLongPtr(window, GWLP_USERDATA);
      if (user_ptr == 0) {
         throw std::runtime_error(std::format("GetWindowLongPtr returned {}", GetLastError()));
      }

      auto *window_class = reinterpret_cast<Window *>(user_ptr);
      window_class->close__internal();
      PostQuitMessage(0);
      return 0;
   }

   return DefWindowProc(window, msg, w_param, l_param);
}

} // namespace

Window::Window(const char *title) : open_(false) {
   HINSTANCE h_instance = GetModuleHandle(nullptr);

   WNDCLASS clazz = {
       .lpfnWndProc = window_proc,
       .hInstance = h_instance,
       .lpszClassName = WIN32_CLASS_NAME,
   };

   if (RegisterClass(&clazz) == 0) {
      throw std::runtime_error(std::format("RegisterClass returned {}", GetLastError()));
   }

   window_ = CreateWindowEx(
       0, WIN32_CLASS_NAME, title, WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT,
       CW_USEDEFAULT, nullptr, nullptr, h_instance, nullptr
   );

   if (window_ == nullptr) {
      throw std::runtime_error(std::format("CreateWindowEx returned {}", GetLastError()));
   }

   SetWindowLongPtr(window_, GWLP_USERDATA, (int64_t)this);

   ShowWindow(window_, SW_SHOW);
   open_ = true;
}

bool Window::poll() {
   MSG msg;
   if (PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE) == 0) {
      return open_;
   }

   TranslateMessage(&msg);
   DispatchMessage(&msg);
   return open_;
}

VkSurfaceKHR Window::create_surface(VkInstance instance) {
   VkWin32SurfaceCreateInfoKHR surface_create = {
       .sType = VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
       .hinstance = GetModuleHandle(nullptr),
       .hwnd = window_,
   };

   VkSurfaceKHR surface;
   if (vkCreateWin32SurfaceKHR(instance, &surface_create, nullptr, &surface) != VK_SUCCESS) {
      throw std::runtime_error("couldn't create win32 surface");
   }

   return surface;
}
