#ifndef VKAD_UI_FONT_H_
#define VKAD_UI_FONT_H_

#include <array>
#include <string>

#include "gpu/image.h"
#include "gpu/physical_device.h"
#include "ui/widget.h"
#include "vendor/stb_truetype.h"

namespace vkad {

class Font {
public:
   Font(
       const unsigned char *data, float height, const PhysicalDevice &physical_device,
       VkDevice device
   );

   Widget create_text(const std::string &text);

   Image &image() {
      return image_;
   }

   unsigned char *image_data() {
      return bitmap_.data();
   }

   static constexpr int kBitmapWidth = 1024;

private:
   static constexpr int kNumChars = 96;

   float height_;
   std::array<unsigned char, kBitmapWidth * kBitmapWidth> bitmap_;
   std::array<stbtt_bakedchar, 96> chars_;
   Image image_;
};

} // namespace vkad

#endif // !VKAD_UI_FONT_H_
