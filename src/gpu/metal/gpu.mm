#include "gpu.h"

#include <stdexcept>

#import <Metal/Metal.h>

using namespace vkad;

Gpu::Gpu() : mt_device_(MTLCreateSystemDefaultDevice()) {
   if (mt_device_ == nullptr) {
      throw std::runtime_error("failed to create metal device");
   }

   library_ = [mt_device_ newDefaultLibrary];
   if (library_ == nullptr) {
      throw std::runtime_error("failed to create metal library");
   }
}

Gpu::~Gpu() {
   [library_ release];
   [mt_device_ release];
}
