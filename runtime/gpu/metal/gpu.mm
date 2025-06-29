#include "gpu.h"

#include <format>
#include <stdexcept>

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include "ffi.h"

using namespace simulo;

Gpu::Gpu() : mt_device_(MTLCreateSystemDefaultDevice()) {
   if (mt_device_ == nullptr) {
      throw std::runtime_error("failed to create metal device");
   }

   NSError *err = nullptr;
   library_ = [mt_device_ newDefaultLibraryWithBundle:[NSBundle mainBundle] error:&err];
   if (err != nullptr) {
      const char *message = [err.localizedDescription UTF8String];
      throw std::runtime_error(std::format("failed to create metal library: {}", message));
   }
}

Gpu::~Gpu() {
   [library_ release];
   [mt_device_ release];
}
