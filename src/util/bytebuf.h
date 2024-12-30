#ifndef VKAD_BYTEBUF_H_
#define VKAD_BYTEBUF_H_

#include <cstddef>
#include <cstdint>
#include <span>
#include <stdexcept>
namespace vkad {

class ByteBuf {
public:
   ByteBuf(const std::span<uint8_t> data) : data_(data) {}

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

private:
   std::span<uint8_t> data_;
   size_t read_index_ = 0;
};

} // namespace vkad

#endif // !VKAD_BYTEBUF_H_
