#ifndef VKAD_UI_TEXT_H_
#define VKAD_UI_TEXT_H_

#include "render/vk_renderer.h"
#include <string>

namespace vkad {

class Ui;

class Text {
public:
   explicit Text(const std::string &text, int font_size) : text_(text), font_size_(font_size) {}

   const std::string &text() const {
      return text_;
   }

   int font_size() const {
      return font_size_;
   }

private:
   std::string text_;
   int font_size_;
   RenderObject render_object_;
};

} // namespace vkad

#endif // !VKAD_UI_TEXT_H_
