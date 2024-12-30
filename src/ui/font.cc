#include "font.h"

#include "gpu/vulkan/physical_device.h"
#include "math/vec2.h"
#include "render/renderer.h"
#include "render/ui.h"
#include "vulkan/vulkan_core.h"

#include <string_view>
#include <vector>

#define STB_TRUETYPE_IMPLEMENTATION
#define STBTT_STATIC
#include "vendor/stb_truetype.h"

using namespace vkad;

Font::Font(
    const unsigned char *data, float height, const PhysicalDevice &physical_device, VkDevice device
)
    : height_(height) {

   stbtt_BakeFontBitmap(
       data, 0, height, bitmap_.data(), kBitmapWidth, kBitmapWidth, 32, kNumChars, chars_.data()
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

      Vec2 pos1 = Vec2(q.x0 + x_off, -q.y0 + y_off) / height_;
      Vec2 pos2 = Vec2(q.x1 + x_off, -q.y1 + y_off) / height_;

      int ind = vertices.size();
      vertices.push_back({{pos1.x, pos1.y, 0}, {q.s0, q.t0}});
      vertices.push_back({{pos2.x, pos1.y, 0}, {q.s1, q.t0}});
      vertices.push_back({{pos2.x, pos2.y, 0}, {q.s1, q.t1}});
      vertices.push_back({{pos1.x, pos2.y, 0}, {q.s0, q.t1}});
      indices.push_back(ind);
      indices.push_back(ind + 1);
      indices.push_back(ind + 2);
      indices.push_back(ind);
      indices.push_back(ind + 2);
      indices.push_back(ind + 3);
      x_off += x;
   }
}
