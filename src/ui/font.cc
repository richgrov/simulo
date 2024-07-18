#include "font.h"
#include "gpu/image.h"
#include "gpu/physical_device.h"
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
