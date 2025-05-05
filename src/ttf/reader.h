#pragma once

#include <chrono>

#include "util/reader.h"

namespace simulo {

class TtfReader : public Reader {
public:
   using Reader::Reader;

   int16_t read_fword() {
      return read_i16();
   }

   double read_fixed() {
      int32_t raw = read_u32();
      return static_cast<double>(raw) / (1 << 16);
   }

   std::chrono::system_clock::time_point read_datetime() {
      if (read_index_ + 8 > data_.size()) {
         throw std::out_of_range("buffer too short to read datetime");
      }

      int64_t result = 0;
      for (int i = 0; i < 8; ++i, ++read_index_) {
         result |= static_cast<int64_t>(data_[read_index_]) << (8 - i) * 8;
      }

      auto seconds = std::chrono::seconds(result - (1970 - 1904) * 365 * 24 * 60 * 60);
      return std::chrono::system_clock::time_point(seconds);
   }
};

} // namespace simulo
