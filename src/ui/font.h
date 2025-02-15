#pragma once

#include <array>
#include <string_view>

#ifndef __APPLE__
#include "gpu/vulkan/buffer.h"
#include "gpu/vulkan/physical_device.h"
#endif
#include "render/renderer.h" // IWYU pragma: export
#include "render/ui.h"
#include "vendor/stb_truetype.h"

namespace vkad {

class Font {
public:
   Font(
       std::span<uint8_t> data, float height, const PhysicalDevice &physical_device, VkDevice device
   );

   void create_text(
       const std::string_view &text, std::vector<UiVertex> &vertices,
       std::vector<VertexIndexBuffer::IndexType> &indices
   );

   void set_image(RenderImage id) {
      image_handle_ = id;
   }

   RenderImage image() const {
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
   RenderImage image_handle_;
};

} // namespace vkad
