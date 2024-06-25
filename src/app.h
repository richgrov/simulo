#ifndef VILLA_APP_H_
#define VILLA_APP_H_

#include "gpu/gpu.h"       // IWYU pragma: export
#include "window/window.h" // IWYU pragma: export

namespace villa {

class App {
public:
   explicit App();

   void run();

private:
   Window window_;
   Gpu gpu_;
};

}; // namespace villa

#endif // !VILLA_APP_H_
