#include "window.h"

#include <Windows.h>
#include <format>
#include <stdexcept>

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

Window::Window() : open_(false) {
   HINSTANCE h_instance = GetModuleHandle(nullptr);

   WNDCLASS clazz = {};
   clazz.lpfnWndProc = window_proc;
   clazz.hInstance = h_instance;
   clazz.lpszClassName = WIN32_CLASS_NAME;

   if (RegisterClass(&clazz) == 0) {
      throw std::runtime_error(std::format("RegisterClass returned {}", GetLastError()));
   }

   HWND window = CreateWindowEx(
       0, WIN32_CLASS_NAME, "hello", WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
       CW_USEDEFAULT, CW_USEDEFAULT, nullptr, nullptr, h_instance, nullptr
   );

   if (window == nullptr) {
      throw std::runtime_error(std::format("CreateWindowEx returned {}", GetLastError()));
   }

   SetWindowLongPtr(window, GWLP_USERDATA, (int64_t)this);

   ShowWindow(window, SW_SHOW);
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
