#pragma once

#include <cstdint>
#include <span>
#include <vector>

namespace simulo {

struct ParsedImage {
   uint32_t width;
   uint32_t height;
   std::vector<uint8_t> data;
};

ParsedImage parse_png(std::span<const uint8_t> data);

} // namespace simulo
