#pragma once

#ifdef __OBJC__
#include <Metal/Metal.h>
#endif

#include <cstdint>
#include <span>

#include "gpu/gpu.h"

namespace vkad {

class Image {
public:
   Image(const Gpu &gpu, std::span<const uint8_t> data, int width, int height);
   ~Image();

#ifdef __OBJC__
   id<MTLTexture> _Nonnull texture() const {
      return texture_;
   }
#endif

private:
#ifdef __OBJC__
   id<MTLTexture> _Nonnull texture_;
#else
   void *texture_;
#endif
};

}; // namespace vkad
