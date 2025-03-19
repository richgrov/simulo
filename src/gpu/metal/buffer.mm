#include "buffer.h"

#include <Metal/Metal.h>

#include <format>
#include <span>
#include <stdexcept>
#include <vector>

#include "gpu/metal/gpu.h"
#include "util/memory.h"

using namespace vkad;

Buffer::Buffer(const Gpu &gpu, std::span<const uint8_t> data) {
   buffer_ = [gpu.device() newBufferWithBytes:data.data()
                                       length:data.size()
                                      options:MTLResourceStorageModeShared];
   if (buffer_ == nullptr) {
      throw std::runtime_error("failed to create metal buffer");
   }
}

Buffer::Buffer(Buffer &&other) : buffer_(other.buffer_) {
   other.buffer_ = nullptr;
}

Buffer::~Buffer() {
   if (buffer_ != nullptr) {
      [buffer_ release];
   }
}

VertexIndexBuffer::VertexIndexBuffer(
    const Gpu &gpu, std::span<uint8_t> data, size_t indices_start_offset, IndexType num_indices
)
    : Buffer(gpu, data), indices_start_offset_(indices_start_offset), num_indices_(num_indices) {}

VertexIndexBuffer VertexIndexBuffer::concat(
    const Gpu &gpu, std::span<const uint8_t> vertex_data, std::span<const IndexType> index_data
) {
   size_t indices_start = align_to(vertex_data.size(), (size_t)4);
   size_t indices_size = index_data.size() * sizeof(IndexType);

   std::vector<uint8_t> data(indices_start + indices_size);
   memcpy(data.data(), vertex_data.data(), vertex_data.size());
   memcpy(data.data() + indices_start, index_data.data(), indices_size);

   return VertexIndexBuffer(gpu, data, indices_start, index_data.size());
}
