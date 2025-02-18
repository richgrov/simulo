#include "buffer.h"

#include <Metal/Metal.h>

#include <format>
#include <span>
#include <stdexcept>

using namespace vkad;

Buffer::Buffer(const Gpu &gpu, std::span<const uint8_t> data) {
   buffer_ = [device_ newBufferWithBytes:data.data()
                                  length:data.size()
                                 options:MTLResourceStorageModeShared];
   if (buffer_ == nullptr) {
      throw std::runtime_error("failed to create metal buffer");
   }
}

Buffer::~Buffer() {
   [buffer_ release];
}
