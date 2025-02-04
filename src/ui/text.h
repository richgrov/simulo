#pragma once

#include "render/vk_renderer.h"
#include "ui/widget.h"
#include <string>

namespace vkad {

class Ui;

class Text : public Widget {
public:
   explicit Text(const std::string &text, int font_size) : text_(text), font_size_(font_size) {}

   const std::string &text() const {
      return text_;
   }

   int font_size() const {
      return font_size_;
   }

   virtual void on_init(WidgetVisitor &visitor) override {
      visitor.on_init_text(*this);
   }

   virtual void on_delete(WidgetVisitor &visitor) override {
      visitor.on_delete_text(*this);
   }

private:
   std::string text_;
   int font_size_;
   RenderObject render_object_;
};

} // namespace vkad
