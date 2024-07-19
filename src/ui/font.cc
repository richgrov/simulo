#include "font.h"
#include "gpu/buffer.h"
#include "gpu/image.h"
#include "gpu/physical_device.h"
#include "ui/ui.h"
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
       reinterpret_cast<unsigned char *>(data.data()), 0, 32, bitmap_.data(), BITMAP_WIDTH,
       BITMAP_WIDTH, 32, NUM_CHARS, chars_.data()
   );
}

void Font::create_text(
    const std::string &text, std::vector<UiVertex> &out_vertices,
    std::vector<VertexIndexBuffer::IndexType> &out_indices
) {
   float x_off = 0;
   for (char c : text) {
      int index = c - 32;
      float x = 0;
      float y = 0;
      stbtt_aligned_quad q;
      stbtt_GetBakedQuad(chars_.data(), 512, 512, index, &x, &y, &q, 1);

      int ind = out_vertices.size();
      out_vertices.push_back({{(q.x0 + x_off) / 32, -q.y0 / 32, 0}, {q.s0, q.t0}});
      out_vertices.push_back({{(q.x1 + x_off) / 32, -q.y0 / 32, 0}, {q.s1, q.t0}});
      out_vertices.push_back({{(q.x1 + x_off) / 32, -q.y1 / 32, 0}, {q.s1, q.t1}});
      out_vertices.push_back({{(q.x0 + x_off) / 32, -q.y1 / 32, 0}, {q.s0, q.t1}});
      out_indices.push_back(ind);
      out_indices.push_back(ind + 1);
      out_indices.push_back(ind + 2);
      out_indices.push_back(ind);
      out_indices.push_back(ind + 2);
      out_indices.push_back(ind + 3);
      x_off += x;
   }
}
