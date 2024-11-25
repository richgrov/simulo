#include "font.h"
#include "gpu/vulkan/buffer.h"
#include "gpu/vulkan/image.h"
#include "gpu/vulkan/physical_device.h"
#include "math/vec2.h"
#include "ui/ui.h"
#include "ui/widget.h"
#include "vulkan/vulkan_core.h"
#include <format>
#include <fstream>
#include <ios>
#include <stdexcept>
#include <vector>

#define STB_TRUETYPE_IMPLEMENTATION
#define STBTT_STATIC
#include "vendor/stb_truetype.h"

using namespace vkad;

Font::Font(
    const unsigned char *data, float height, const PhysicalDevice &physical_device, VkDevice device
)
    : height_(height),
      image_(
          physical_device, device, VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
          VK_FORMAT_R8_UNORM, kBitmapWidth, kBitmapWidth
      ) {

   stbtt_BakeFontBitmap(
       data, 0, height, bitmap_.data(), kBitmapWidth, kBitmapWidth, 32, kNumChars, chars_.data()
   );
}

Widget Font::create_text(const std::string &text) {
   std::vector<UiVertex> vertices;
   std::vector<VertexIndexBuffer::IndexType> indices;

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

   return Widget(std::move(vertices), std::move(indices));
}
