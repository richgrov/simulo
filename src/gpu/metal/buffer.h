#pragma once

#include <span>

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

#include "gpu/gpu.h"

namespace vkad {

class Buffer {
public:
   Buffer(const Gpu &gpu, std::span<const uint8_t> data);
   ~Buffer();

   Buffer(const Buffer &other) = delete;
   Buffer &operator=(const Buffer &other) = delete;

#ifdef __OBJC__
   id<MTLBuffer> _Nonnull buffer() const {
      return buffer_;
   }
#endif

protected:
#ifdef __OBJC__
   id<MTLBuffer> _Nonnull buffer_;
#else
   void *buffer_;
#endif
};

} // namespace vkad
