#ifndef VKAD_UTIL_BITFIELD_H_
#define VKAD_UTIL_BITFIELD_H_

#include <cstring>

namespace vkad {

template <int Bits> class Bitfield {
   static constexpr size_t NUM_BYTES = (Bits + (8 - Bits % 8) % 8) / 8;

public:
   Bitfield() : bytes_{} {}

   Bitfield &operator=(const Bitfield &other) {
      std::memcpy(bytes_, other.bytes_, NUM_BYTES);
      return *this;
   }

   inline bool operator[](size_t index) const {
      unsigned char byte = bytes_[index / 8];
      return (byte >> (index % 8)) & 1;
   }

   inline void set(size_t index) {
      bytes_[index / 8] |= (1 << (index % 8));
   }

   inline void unset(size_t index) {
      bytes_[index / 8] &= ~(1 << (index % 8));
   }

private:
   unsigned char bytes_[NUM_BYTES];
};

} // namespace vkad

#endif // !VKAD_UTIL_BITFIELD_H_
