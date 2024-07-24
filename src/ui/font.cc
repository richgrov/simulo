#include "font.h"
#include "gpu/buffer.h"
#include "gpu/image.h"
#include "gpu/physical_device.h"
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

Font::Font(const std::string &path, const PhysicalDevice &physical_device, VkDevice device)
    : image_(
          physical_device, device, VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
          VK_FORMAT_R8_UNORM, BITMAP_WIDTH, BITMAP_WIDTH
      ) {

   std::ifstream file(path, std::ios::ate | std::ios::binary);
   if (!file.is_open()) {
      throw std::runtime_error(std::format("failed to open {}", path));
   }

   std::streamsize size = file.tellg();
   file.seekg(0, std::ios::beg);

   std::vector<char> data(size);
   if (!file.read(data.data(), size)) {
      throw std::runtime_error(std::format("failed to read {}", path));
   }

   stbtt_BakeFontBitmap(
       reinterpret_cast<unsigned char *>(data.data()), 0, 64, bitmap_.data(), BITMAP_WIDTH,
       BITMAP_WIDTH, 32, NUM_CHARS, chars_.data()
   );
}

Widget Font::create_text(const std::string &text) {
   std::vector<UiVertex> vertices;
   std::vector<VertexIndexBuffer::IndexType> indices;

   float x_off = 0;
   for (char c : text) {
      int index = c - 32;
      float x = 0;
      float y = 0;
      stbtt_aligned_quad q;
      stbtt_GetBakedQuad(chars_.data(), BITMAP_WIDTH, BITMAP_WIDTH, index, &x, &y, &q, 1);

      int ind = vertices.size();
      vertices.push_back({{(q.x0 + x_off) / 32, -q.y0 / 32, 0}, {q.s0, q.t0}});
      vertices.push_back({{(q.x1 + x_off) / 32, -q.y0 / 32, 0}, {q.s1, q.t0}});
      vertices.push_back({{(q.x1 + x_off) / 32, -q.y1 / 32, 0}, {q.s1, q.t1}});
      vertices.push_back({{(q.x0 + x_off) / 32, -q.y1 / 32, 0}, {q.s0, q.t1}});
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
