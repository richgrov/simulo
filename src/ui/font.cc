#include "font.h"

#include "gpu/vulkan/physical_device.h"
#include "math/vec2.h"
#include "render/renderer.h"
#include "render/ui.h"
#include "util/bytebuf.h"
#include "vulkan/vulkan_core.h"

#include <cstdint>
#include <stdexcept>
#include <string_view>
#include <vector>

#define STB_TRUETYPE_IMPLEMENTATION
#include "vendor/stb_truetype.h"

using namespace vkad;

namespace {

constexpr uint32_t SCALAR_TYPE_TRUE1 = 0x74727565;
constexpr uint32_t SCALAR_TYPE_TRUE2 = 0x00010000;

void read_font_directory(ByteBuf &buf) {
   uint32_t scaler_type = buf.read_u32();
   if (scaler_type != SCALAR_TYPE_TRUE1 && scaler_type != SCALAR_TYPE_TRUE2) {
      throw std::runtime_error(std::format("font has invalid scalar type {}", scaler_type));
   }

   uint16_t num_tables = buf.read_u16();
   buf.read_u16(); // search range
   buf.read_u16(); // entry selector
   buf.read_u16(); // range shift

   for (int i = 0; i < num_tables; ++i) {
      uint32_t tag = buf.read_u32();
      uint32_t checksum = buf.read_u32();
      uint32_t offset = buf.read_u32();
      uint32_t length = buf.read_u32();

      std::cout << (char)(tag >> 24) << (char)(tag >> 16 & 0xFF) << (char)(tag >> 8 & 0xFF)
                << (char)(tag & 0xFF) << '\n';
   }
}

} // namespace

Font::Font(
    std::span<uint8_t> data, float height, const PhysicalDevice &physical_device, VkDevice device
)
    : height_(height) {

   ByteBuf file(data);
   read_font_directory(file);

   stbtt_BakeFontBitmap(
       data.data(), 0, height, bitmap_.data(), kBitmapWidth, kBitmapWidth, 32, kNumChars,
       chars_.data()
   );
}

void Font::create_text(
    const std::string_view &text, std::vector<UiVertex> &vertices,
    std::vector<Renderer::IndexBufferType> &indices
) {
   float x_off = 0;
   float y_off = 0;
   for (char c : text) {
      if (c == '\n') {
         x_off = 0;
         y_off -= 1 * height_;
         continue;
      }

      int index = c - 32;
      float x = 0;
      float y = 0;
      stbtt_aligned_quad q;
      stbtt_GetBakedQuad(chars_.data(), kBitmapWidth, kBitmapWidth, index, &x, &y, &q, 1);

      Vec2 pos1 = Vec2{q.x0 + x_off, -q.y0 + y_off} / height_;
      Vec2 pos2 = Vec2{q.x1 + x_off, -q.y1 + y_off} / height_;

      int ind = vertices.size();
      vertices.push_back({{pos1.x(), pos1.y(), 0}, {q.s0, q.t0}});
      vertices.push_back({{pos2.x(), pos1.y(), 0}, {q.s1, q.t0}});
      vertices.push_back({{pos2.x(), pos2.y(), 0}, {q.s1, q.t1}});
      vertices.push_back({{pos1.x(), pos2.y(), 0}, {q.s0, q.t1}});
      indices.push_back(ind);
      indices.push_back(ind + 1);
      indices.push_back(ind + 2);
      indices.push_back(ind);
      indices.push_back(ind + 2);
      indices.push_back(ind + 3);
      x_off += x;
   }
}
