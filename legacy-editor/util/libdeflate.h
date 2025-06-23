#pragma once

#include <format>
#include <libdeflate.h>
#include <memory>
#include <span>

namespace simulo {

class Decompressor {
public:
   Decompressor() : decompressor_(libdeflate_alloc_decompressor(), libdeflate_free_decompressor) {}

   void zlib_decompress(std::span<const uint8_t> input, std::span<uint8_t> output) {
      libdeflate_result res = libdeflate_zlib_decompress(
          decompressor_.get(), input.data(), input.size(), output.data(), output.size(), nullptr
      );

      switch (res) {
      case LIBDEFLATE_SUCCESS:
         return;

      case LIBDEFLATE_BAD_DATA:
         throw std::runtime_error("corrupt compressed data");

      case LIBDEFLATE_SHORT_OUTPUT:
         throw std::runtime_error(
             std::format("uncompressed data was shorter than {} expected bytes", output.size())
         );

      case LIBDEFLATE_INSUFFICIENT_SPACE:
         throw std::runtime_error(
             std::format("uncompressed data was longer than {} expected bytes", output.size())
         );
      }
   }

private:
   std::unique_ptr<libdeflate_decompressor, decltype(&libdeflate_free_decompressor)> decompressor_;
};

} // namespace simulo
