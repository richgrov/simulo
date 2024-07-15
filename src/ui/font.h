#ifndef VKAD_UI_FONT_H_
#define VKAD_UI_FONT_H_

#include <array>
#include <string>

#include "gpu/image.h"
#include "gpu/physical_device.h"
#include "vendor/stb_truetype.h"

namespace vkad {

class Font {
public:
   Font(const std::string &path, const PhysicalDevice &physical_device, VkDevice device);

private:
   static constexpr int BITMAP_WIDTH = 512;
   static constexpr int NUM_CHARS = 96;

   std::array<unsigned char, BITMAP_WIDTH * BITMAP_WIDTH> bitmap_;
   std::array<stbtt_bakedchar, 96> chars_;
   Image image_;
};

} // namespace vkad

#endif // !VKAD_UI_FONT_H_
