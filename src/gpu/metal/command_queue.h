#pragma once

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

#include "gpu/gpu.h"

namespace vkad {

class CommandQueue {
public:
   CommandQueue(const Gpu &gpu);
   ~CommandQueue();

private:
#ifdef __OBJC__
   id<MTLCommandQueue> command_queue_;
#else
   void *command_queue_;
#endif
};

} // namespace vkad
