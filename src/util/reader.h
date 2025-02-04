#pragma once

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

   void seek(size_t position) {
      if (position < 0 || position > data_.size()) {
         throw std::out_of_range(std::format("seek position {} is out of range", position));
      }
      read_index_ = position;
   }

   size_t position() const {
      return read_index_;
   }

protected:
   std::span<uint8_t> data_;
   size_t read_index_ = 0;
};

} // namespace vkad
