#include "ttf.h"
#include "ttf/reader.h"
#include <iostream>
#include <stdexcept>
#include <vector>

using namespace simulo;

namespace {

constexpr uint32_t SCALAR_TYPE_TRUE1 = 0x74727565;
constexpr uint32_t SCALAR_TYPE_TRUE2 = 0x00010000;

constexpr uint32_t HEAD_MAGIC_NUMBER = 0x5F0F3CF5;

constexpr uint32_t TAG_HEAD = 'h' << 24 | 'e' << 16 | 'a' << 8 | 'd';
constexpr uint32_t TAG_GLYF = 'g' << 24 | 'l' << 16 | 'y' << 8 | 'f';

void read_head(TtfReader &file) {
   std::cout << file.read_fixed() << "\n"; // version
   std::cout << file.read_fixed() << "\n"; // font revision
   std::cout << file.read_u32() << "\n";   // check sum adjustment

   if (auto magic_num = file.read_u32(); magic_num != HEAD_MAGIC_NUMBER) {
      throw std::runtime_error(std::format("bad header magic number: {}", magic_num));
   }

   std::cout << file.read_u16() << "\n";      // flags
   std::cout << file.read_u16() << "\n";      // units per em
   std::cout << file.read_datetime() << "\n"; // created
   std::cout << file.read_datetime() << "\n"; // modified
   std::cout << file.read_fword() << "\n";    // x min
   std::cout << file.read_fword() << "\n";    // y min
   std::cout << file.read_fword() << "\n";    // x max
   std::cout << file.read_fword() << "\n";    // y max
   std::cout << file.read_u16() << "\n";      // mac style
   std::cout << file.read_u16() << "\n";      // lowest rec ppem
   std::cout << file.read_i16() << "\n";      // font direction hint
   std::cout << file.read_i16() << "\n";      // index to loc format
   std::cout << file.read_i16() << "\n";      // glyph data format
}

void read_glyf(Reader &file) {
   int16_t num_contours = file.read_i16();
   int16_t x_min = file.read_i16();
   int16_t y_min = file.read_i16();
   int16_t x_max = file.read_i16();
   int16_t y_max = file.read_i16();
   std::cout << num_contours << " contours from (" << x_min << ", " << y_min << ") to (" << x_max
             << ", " << y_max << ")\n";

   if (num_contours >= 0) {
      std::vector<uint16_t> contour_end_points(num_contours);
      for (int i = 0; i < num_contours; ++i) {
         contour_end_points[i] = file.read_u16();
      }

      uint16_t instruction_len = file.read_u16();
      std::vector<uint8_t> instructions(instruction_len);
      for (int i = 0; i < instruction_len; ++i) {
         instructions[i] = file.read_u8();
      }
   } else {
   }
}

} // namespace

void simulo::read_ttf(const std::span<const uint8_t> data) {
   TtfReader file(data);

   uint32_t scaler_type = file.read_u32();
   if (scaler_type != SCALAR_TYPE_TRUE1 && scaler_type != SCALAR_TYPE_TRUE2) {
      throw std::runtime_error(std::format("font has invalid scalar type {}", scaler_type));
   }

   uint16_t num_tables = file.read_u16();
   file.read_u16(); // search range
   file.read_u16(); // entry selector
   file.read_u16(); // range shift

   for (int i = 0; i < num_tables; ++i) {
      uint32_t tag = file.read_u32();
      uint32_t checksum = file.read_u32();
      uint32_t offset = file.read_u32();
      uint32_t length = file.read_u32();

      size_t position = file.position();
      file.seek(offset);

      switch (tag) {
      case TAG_GLYF:
         read_glyf(file);
         break;

      case TAG_HEAD:
         read_head(file);
         break;
      }

      file.seek(position);
   }
}
