#pragma once

#include <cstdint>
#include <format>
#include <span>
#include <stdexcept>
#include <vector>

namespace vkad {

class Reader {
public:
   Reader(const std::span<const uint8_t> data) : data_(data) {}

   template <class T> inline T read() {
      if (read_index_ + sizeof(T) > data_.size()) {
         throw std::out_of_range(std::format("buffer too short to read {}", typeid(T).name()));
      }

      T result = 0;
      for (size_t i = 0; i < sizeof(T); ++i) {
         result |= static_cast<T>(data_[read_index_++]) << (sizeof(T) - 1 - i) * 8;
      }

      return result;
   }

   uint8_t read_u8() {
      return read<uint8_t>();
   }

   uint16_t read_i16() {
      return read<int16_t>();
   }

   uint16_t read_u16() {
      return read<uint16_t>();
   }

   uint32_t read_u32() {
      return read<uint32_t>();
   }

   uint64_t read_u64() {
      return read<uint64_t>();
   }

   void read_into(std::vector<uint8_t> &dest, size_t size) {
      if (read_index_ + size > data_.size()) {
         throw std::out_of_range(std::format("buffer too short to read {} bytes", dest.size()));
      }

      dest.insert(dest.end(), data_.begin() + read_index_, data_.begin() + read_index_ + size);
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
   std::span<const uint8_t> data_;
   size_t read_index_ = 0;
};

} // namespace vkad
