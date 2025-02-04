#pragma once

#include <chrono>
#include <cstdint>
#include <format>
#include <span>
#include <stdexcept>

namespace vkad {

class Reader {
public:
   Reader(const std::span<uint8_t> data) : data_(data) {}

   uint8_t read_u8() {
      if (read_index_ + 1 > data_.size()) {
         throw std::out_of_range("buffer too short to read u8");
      }
      return data_[read_index_++];
   }

   int16_t read_i16() {
      return static_cast<int16_t>(read_u16());
   }

   int16_t read_fword() {
      return read_i16();
   }

   uint16_t read_u16() {
      if (read_index_ + 2 > data_.size()) {
         throw std::out_of_range("buffer too short to read u16");
      }

      uint32_t result = data_[read_index_] << 8 | data_[read_index_ + 1];
      read_index_ += 2;

      return result;
   }

   uint32_t read_u32() {
      if (read_index_ + 4 > data_.size()) {
         throw std::out_of_range("buffer too short to read u32");
      }

      uint32_t result = data_[read_index_] << 24 | data_[read_index_ + 1] << 16 |
                        data_[read_index_ + 2] << 8 | data_[read_index_ + 3];
      read_index_ += 4;

      return result;
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

   void seek(size_t position) {
      if (position < 0 || position > data_.size()) {
         throw std::out_of_range(std::format("seek position {} is out of range", position));
      }
      read_index_ = position;
   }

   size_t position() const {
      return read_index_;
   }

private:
   std::span<uint8_t> data_;
   size_t read_index_ = 0;
};

} // namespace vkad
