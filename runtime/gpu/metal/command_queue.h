#pragma once

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

#include "gpu/gpu.h"

namespace simulo {

class CommandQueue {
public:
   CommandQueue(const Gpu &gpu);
   ~CommandQueue();

#ifdef __OBJC__
   id<MTLCommandBuffer> _Nullable command_buffer() const {
      return command_queue_.commandBuffer;
   }
#endif

private:
#ifdef __OBJC__
   id<MTLCommandQueue> _Nonnull command_queue_;
#else
   void *command_queue_;
#endif
};

} // namespace simulo
