#ifndef VILLA_WINDOW_WIN32_WINDOW_H_
#define VILLA_WINDOW_WIN32_WINDOW_H_

#include <Windows.h>

namespace villa {

class Window {
public:
   explicit Window(const char *title);

   bool poll();

   inline void close__internal() {
      open_ = false;
   }

private:
   HWND window_;
   bool open_;
};

}; // namespace villa

#endif // !VILLA_WINDOW_WIN32_WINDOW_H_
