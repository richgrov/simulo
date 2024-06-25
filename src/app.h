#ifndef VILLA_APP_H_
#define VILLA_APP_H_

#include "window/window.h" // IWYU pragma: export

namespace villa {

class App {
public:
   App();

   void run();

private:
   Window window_;
};

}; // namespace villa

#endif // !VILLA_APP_H_
