#include "command_queue.h"

#include <Metal/Metal.h>
#include <stdexcept>

#include "gpu/gpu.h"

using namespace simulo;

CommandQueue::CommandQueue(const Gpu &gpu) : command_queue_([gpu.device() newCommandQueue]) {
   if (command_queue_ == nullptr) {
      throw std::runtime_error("failed to create command queue");
   }
}

CommandQueue::~CommandQueue() {
   [command_queue_ release];
}
