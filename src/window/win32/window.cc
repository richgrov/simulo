#include "window.h"

#include <cstring>
#include <format>
#include <stdexcept>
#include <windowsx.h>

#include <hidusage.h>
#include <vulkan/vulkan_core.h>
#define VK_USE_PLATFORM_WIN32_KHR
#include <Windows.h> // IWYU pragma: export
#include <vulkan/vulkan_win32.h>

#include "gpu/vulkan/status.h"

using namespace simulo;

namespace {

const char *WIN32_CLASS_NAME = "simulo";

static Window *get_window_class(HWND window) {
   LONG_PTR user_ptr = GetWindowLongPtr(window, GWLP_USERDATA);
   if (user_ptr == 0) {
      throw std::runtime_error(std::format("GetWindowLongPtr returned {}", GetLastError()));
   }

   return reinterpret_cast<Window *>(user_ptr);
}

void register_raw_mouse_input(HWND window) {
   RAWINPUTDEVICE device = {
       .usUsagePage = HID_USAGE_PAGE_GENERIC,
       .usUsage = HID_USAGE_GENERIC_MOUSE,
       .dwFlags = RIDEV_INPUTSINK,
       .hwndTarget = window,
   };

   if (!RegisterRawInputDevices(&device, 1, sizeof(device))) {
      throw std::runtime_error(std::format("failed to record mouse input: {}", GetLastError()));
   }
}

VkSurfaceKHR create_surface(HWND window, VkInstance instance) {
   VkWin32SurfaceCreateInfoKHR surface_create = {
       .sType = VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
       .hinstance = GetModuleHandle(nullptr),
       .hwnd = window,
   };

   VkSurfaceKHR surface;
   VKAD_VK(vkCreateWin32SurfaceKHR(instance, &surface_create, nullptr, &surface));
   return surface;
}

} // namespace

LRESULT CALLBACK simulo::window_proc(HWND window, UINT msg, WPARAM w_param, LPARAM l_param) {
   switch (msg) {
   case WM_DESTROY:
      get_window_class(window)->open_ = false;
      PostQuitMessage(0);
      return 0;

   case WM_SIZE: {
      WORD height = HIWORD(l_param);
      WORD width = LOWORD(l_param);
      auto window_class = get_window_class(window);
      window_class->width_ = width;
      window_class->height_ = height;
      return 0;
   }

   case WM_MOVE: {
      Window *window_cls = get_window_class(window);
      window_cls->window_x_ = LOWORD(l_param);
      window_cls->window_y_ = HIWORD(l_param);
      return 0;
   }

   case WM_INPUT: {
      RAWINPUT input;
      UINT size = sizeof(input);
      GetRawInputData(
          reinterpret_cast<HRAWINPUT>(l_param), RID_INPUT, &input, &size, sizeof(RAWINPUTHEADER)
      );

      if (input.header.dwType == RIM_TYPEMOUSE) {
         Window *window_cls = get_window_class(window);
         window_cls->delta_mouse_x_ = input.data.mouse.lLastX;
         window_cls->delta_mouse_y_ = -input.data.mouse.lLastY; // Negate so positive is up
         USHORT flags = input.data.mouse.usFlags;
      }
      return 0;
   }

   case WM_MOUSEMOVE: {
      int x = GET_X_LPARAM(l_param);
      int y = GET_Y_LPARAM(l_param);
      Window *window_class = get_window_class(window);
      window_class->mouse_x_ = x;
      window_class->mouse_y_ = y;
      return 0;
   }

   case WM_LBUTTONDOWN:
      get_window_class(window)->left_clicking_ = true;
      return 0;

   case WM_LBUTTONUP:
      get_window_class(window)->left_clicking_ = false;
      return 0;

   case WM_KEYDOWN:
      get_window_class(window)->pressed_keys_.set(static_cast<uint8_t>(w_param));
      return 0;

   case WM_KEYUP:
      get_window_class(window)->pressed_keys_.unset(static_cast<uint8_t>(w_param));
      return 0;

   case WM_CHAR: {
      Window *window_class = get_window_class(window);
      if (window_class->next_typed_letter_ < sizeof(window_class->typed_chars_)) {
         char c = static_cast<char>(w_param);
         window_class->typed_chars_[window_class->next_typed_letter_++] = c;
      }
   }
      return 0;
   }

   return DefWindowProc(window, msg, w_param, l_param);
}

Window::Window(const Instance &vk_instance, const char *title)
    : vk_instance_(vk_instance),
      open_(false),
      closing_(false),
      cursor_captured_(false),
      window_x_(0),
      window_y_(0),
      width_(0),
      height_(0),
      mouse_x_(0),
      mouse_y_(0),
      delta_mouse_x_(0),
      delta_mouse_y_(0),
      left_clicking_(false),
      typed_chars_{},
      next_typed_letter_(0) {
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

   register_raw_mouse_input(window_);
   surface_ = create_surface(window_, vk_instance.handle());
}

Window::~Window() {
   vkDestroySurfaceKHR(vk_instance_.handle(), surface_, nullptr);
}

bool Window::poll() {
   prev_pressed_keys_ = pressed_keys_;
   std::memset(typed_chars_, 0, sizeof(typed_chars_));
   next_typed_letter_ = 0;

   // Reset mouse deltas as WM_INPUT is not guaranteed to be received every frame
   delta_mouse_x_ = 0;
   delta_mouse_y_ = 0;

   if (cursor_captured_ && width_ != 0 && height_ != 0) {
      SetCursorPos(window_x_ + width_ / 2, window_y_ + height_ / 2);
   }

   MSG msg;
   while (PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE) != 0) {
      TranslateMessage(&msg);
      DispatchMessage(&msg);
   }

   return open_;
}

void Window::set_capture_mouse(bool capture) {
   cursor_captured_ = capture;

   if (capture) {
      SetCapture(window_);
   } else {
      ReleaseCapture();
   }
   ShowCursor(!capture);
}

void Window::request_close() {
   if (open_ && !closing_) {
      PostMessage(window_, WM_CLOSE, 0, 0);
      closing_ = true;
   }
}
