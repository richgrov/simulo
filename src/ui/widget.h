#ifndef VKAD_UI_WIDGET_H_
#define VKAD_UI_WIDGET_H_

#include "math/mat4.h"
#include "render/renderer.h" // IWYU pragma: export

namespace vkad {

class Text;

class WidgetVisitor {
public:
   virtual void on_init_text(Text &text) {}
   virtual void on_delete_text(Text &text) {}
};

class Widget {
public:
   Widget() = default;
   virtual ~Widget() = default;

   inline void set_position(int x, int y) {
      x_ = x;
      y_ = y;
   }

   inline void set_size(int size) {
      scale_ = size;
   }

   inline Mat4 transform() const {
      auto x = static_cast<float>(x_);
      auto y = static_cast<float>(y_);
      auto scale = static_cast<float>(scale_);
      return Mat4::translate(Vec3{x, y, 0.f}) * Mat4::scale(Vec3{scale, scale, 1.f});
   }

   virtual void on_init(WidgetVisitor &visitor) {}
   virtual void on_delete(WidgetVisitor &visitor) {}

   RenderObject renderer_handle_;

private:
   int x_;
   int y_;
   int scale_;
};

} // namespace vkad

#endif // !VKAD_UI_WIDGET_H_
