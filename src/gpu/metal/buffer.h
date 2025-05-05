#pragma once

#include <span>

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

#include "gpu/gpu.h"

namespace simulo {

class Buffer {
public:
   Buffer(const Gpu &gpu, std::span<const uint8_t> data);
   Buffer(Buffer &&other);
   ~Buffer();

   Buffer(const Buffer &other) = delete;
   Buffer &operator=(const Buffer &other) = delete;
   Buffer &operator=(Buffer &&other) = delete;

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

class VertexIndexBuffer : public Buffer {
public:
   using IndexType = uint16_t;
#ifdef __OBJC__
   static constexpr MTLIndexType kIndexType = MTLIndexTypeUInt16;
#endif

   VertexIndexBuffer(
       const Gpu &gpu, std::span<uint8_t> data, size_t indices_start_offset, IndexType num_indices
   );

   static VertexIndexBuffer concat(
       const Gpu &gpu, std::span<const uint8_t> vertex_data, std::span<const IndexType> index_data
   );

   inline IndexType num_indices() const {
      return num_indices_;
   }

   inline size_t index_offset() const {
      return indices_start_offset_;
   }

private:
   size_t indices_start_offset_;
   IndexType num_indices_;
};

} // namespace simulo
