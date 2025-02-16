#include "gpu.h"

#include <stdexcept>

#import <Metal/Metal.h>

using namespace vkad;

Gpu::Gpu() : mt_device_(MTLCreateSystemDefaultDevice()) {
   auto mt_device = reinterpret_cast<id<MTLDevice>>(mt_device_);

   library_ = [mt_device newDefaultLibrary];
   if (library_ == nullptr) {
      throw std::runtime_error("failed to create metal library");
   }
}

Gpu::~Gpu() {
   [reinterpret_cast<id<MTLLibrary>>(library_) release];
   [reinterpret_cast<id<MTLDevice>>(mt_device_) release];
}
