#include "png.h"

#include <format>
#include <stdexcept>

#include "util/libdeflate.h"
#include "util/reader.h"
#include "vendor/libdeflate/libdeflate.h"

using namespace simulo;

namespace {

constexpr uint64_t PNG_HEADER = 0x89504e470d0a1a0a;
constexpr uint32_t CHUNK_IHDR = 'I' << 24 | 'H' << 16 | 'D' << 8 | 'R';
constexpr uint32_t CHUNK_IDAT = 'I' << 24 | 'D' << 16 | 'A' << 8 | 'T';
constexpr uint32_t CHUNK_IEND = 'I' << 24 | 'E' << 16 | 'N' << 8 | 'D';
constexpr uint8_t COLOR_TYPE_RGBA = 6;
constexpr uint8_t FILTER_NONE = 0;
constexpr uint8_t FILTER_SUB = 1;
constexpr uint8_t FILTER_UP = 2;
constexpr uint8_t FILTER_AVERAGE = 3;
constexpr uint8_t FILTER_PAETH = 4;

struct Chunk {
   uint32_t length;
   uint32_t type;
   size_t data_start;
   uint32_t crc;
};

Chunk read_chunk(Reader &reader) {
   Chunk chunk = {
       .length = reader.read_u32(),
       .type = reader.read_u32(),
       .data_start = reader.position(),
   };
   reader.seek(chunk.data_start + chunk.length);
   chunk.crc = reader.read_u32();
   return chunk;
}

struct Ihdr {
   uint32_t width;
   uint32_t height;
   uint8_t bit_depth;
   uint8_t color_type;
   uint8_t compression;
   uint8_t filter;
   uint8_t interlace;
};

Ihdr read_ihdr(Reader &reader) {
   return Ihdr{
       .width = reader.read_u32(),
       .height = reader.read_u32(),
       .bit_depth = reader.read_u8(),
       .color_type = reader.read_u8(),
       .compression = reader.read_u8(),
       .filter = reader.read_u8(),
       .interlace = reader.read_u8(),
   };
}

uint8_t paeth(uint8_t prev, uint8_t above, uint8_t prev_above) {
   uint8_t p = prev + above - prev_above;
   uint8_t prev_dist = std::abs(prev - prev_above);
   uint8_t above_dist = std::abs(above - prev_above);
   uint8_t prev_above_dist = std::abs(prev - prev_above);
   if (prev_dist < above_dist && prev_dist < prev_above_dist) {
      return prev;
   } else if (above_dist < prev_dist && above_dist < prev_above_dist) {
      return above;
   } else {
      return prev_above;
   }
}

} // namespace

ParsedImage simulo::parse_png(std::span<const uint8_t> data) {
   Reader reader(data);

   if (uint64_t header = reader.read_u64(); header != PNG_HEADER) {
      throw std::runtime_error(std::format("invalid header: {}", header));
   }

   std::vector<Chunk> chunks;
   chunks.reserve(3);

   while (true) {
      Chunk chunk = read_chunk(reader);
      if (chunk.type == CHUNK_IEND) {
         break;
      }
      chunks.push_back(chunk);
   }

   if (chunks.size() < 3) {
      throw std::runtime_error("png didn't contain at least 3 chunks");
   }

   Chunk &ihdr_chunk = chunks[0];
   if (ihdr_chunk.type != CHUNK_IHDR) {
      throw std::runtime_error("first chunk wasn't IHDR");
   }

   size_t current_pos = reader.position();
   reader.seek(ihdr_chunk.data_start);
   Ihdr ihdr = read_ihdr(reader);
   reader.seek(current_pos);

   if (ihdr.width == 0 || ihdr.height == 0) {
      throw std::runtime_error(
          std::format("invalid image dimension: {}x{}", ihdr.width, ihdr.height)
      );
   }

   if (ihdr.bit_depth != 8) {
      throw std::runtime_error(std::format("image bit depth not supported: {}", ihdr.bit_depth));
   }

   if (ihdr.color_type != COLOR_TYPE_RGBA) {
      throw std::runtime_error(std::format("image bit depth not supported: {}", ihdr.bit_depth));
   }

   if (ihdr.compression != 0 || ihdr.filter != 0 || ihdr.interlace != 0) {
      throw std::runtime_error(std::format(
          "compression, filter, interlace not supported: {}, {}, {}", ihdr.compression, ihdr.filter,
          ihdr.interlace
      ));
   }

   std::vector<uint8_t> compressed_pixels;
   for (Chunk &chunk : chunks) {
      if (chunk.type != CHUNK_IDAT) {
         continue;
      }

      reader.seek(chunk.data_start);
      reader.read_into(compressed_pixels, chunk.length);
   }

   std::vector<uint8_t> decompressed_pixels((ihdr.width * 4 + 1) * ihdr.height);
   Decompressor deflator;
   deflator.zlib_decompress(compressed_pixels, decompressed_pixels);

   std::vector<uint8_t> result(ihdr.width * ihdr.height * 4);

   size_t row_stride = ihdr.width * 4 + 1;
   for (size_t y = 0; y < ihdr.height; ++y) {
      uint8_t filter = decompressed_pixels[y * row_stride];
      switch (filter) {
      case FILTER_NONE:
      case FILTER_SUB:
      case FILTER_UP:
      case FILTER_AVERAGE:
      case FILTER_PAETH:
         break;
      }

      for (size_t x = 1; x < ihdr.width; ++x) {
         uint8_t byte = decompressed_pixels[y * row_stride + x];
         size_t result_idx = y * ihdr.width * 4 + x;

         if (filter == FILTER_NONE) {
            result[result_idx] = byte;
            continue;
         }

         if (filter == FILTER_SUB) {
            uint8_t prev = x == 1 ? 0 : decompressed_pixels[y * row_stride + x - 1];
            result[result_idx] = byte + prev;
            continue;
         }

         if (filter == FILTER_UP) {
            uint8_t above = y == 0 ? 0 : decompressed_pixels[(y - 1) * row_stride + x];
            result[result_idx] = byte + above;
            continue;
         }

         if (filter == FILTER_AVERAGE) {
            uint8_t prev = x == 1 ? 0 : decompressed_pixels[y * row_stride + x - 1];
            uint8_t above = y == 0 ? 0 : decompressed_pixels[(y - 1) * row_stride + x];
            result[result_idx] = byte + (prev + above) / 2;
            continue;
         }

         if (filter == FILTER_PAETH) {
            uint8_t prev = x == 1 ? 0 : decompressed_pixels[y * row_stride + x - 1];
            uint8_t above = y == 0 ? 0 : decompressed_pixels[(y - 1) * row_stride + x];
            uint8_t prev_above =
                (x == 1 || y == 0) ? 0 : decompressed_pixels[(y - 1) * row_stride + x - 1];
            result[result_idx] = paeth(prev, above, prev_above);
            continue;
         }

         throw std::runtime_error(std::format("invalid filter: {}", filter));
      }
   }

   return ParsedImage{
       .width = ihdr.width,
       .height = ihdr.height,
       .data = std::move(result),
   };
}
