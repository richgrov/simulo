#ifndef VKAD_UI_FONT_H_
#define VKAD_UI_FONT_H_

#include <array>
#include <string>

#include "gpu/buffer.h"
#include "gpu/image.h"
#include "gpu/physical_device.h"
#include "ui/ui.h"
#include "vendor/stb_truetype.h"

namespace vkad {

class Font {
public:
   Font(const std::string &path, const PhysicalDevice &physical_device, VkDevice device);

   void create_text(
       const std::string &text, std::vector<UiVertex> &out_vertices,
       std::vector<VertexIndexBuffer::IndexType> &out_indices
   );

   Image &image() {
      return image_;
   }

   unsigned char *image_data() {
      return bitmap_.data();
   }

   static constexpr int BITMAP_WIDTH = 1024;
   
private:
   static constexpr int NUM_CHARS = 96;

   std::array<unsigned char, BITMAP_WIDTH * BITMAP_WIDTH> bitmap_;
   std::array<stbtt_bakedchar, 96> chars_;
   Image image_;
};

} // namespace vkad

#endif // !VKAD_UI_FONT_H_
