#ifndef VKAD_UI_FONT_H_
#define VKAD_UI_FONT_H_

#include <array>
#include <string>

#include "gpu/vulkan/physical_device.h"
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

   void set_image(int id) {
      image_handle_ = id;
   }

   int image() const {
      return image_handle_;
   }

   std::span<unsigned char> image_data() {
      return bitmap_;
   }

   static constexpr int kBitmapWidth = 1024;

private:
   static constexpr int kNumChars = 96;

   float height_;
   std::array<unsigned char, kBitmapWidth * kBitmapWidth> bitmap_;
   std::array<stbtt_bakedchar, 96> chars_;
   int image_handle_;
};

} // namespace vkad

#endif // !VKAD_UI_FONT_H_
