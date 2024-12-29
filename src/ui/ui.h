#ifndef VKAD_UI_UI_H_
#define VKAD_UI_UI_H_

#include <vector>

#include "render/renderer.h" // IWYU pragma: export
#include "ui/font.h"
#include "ui/text.h"

namespace vkad {

class Ui {
public:
   Ui(Renderer &renderer);

   void add_child(Text &&text);

   int num_children() const {
      return children_.size();
   }

   void delete_child(int index);

private:
   Renderer &renderer_;
   RenderMaterial white_text_;
   Font font_;
   std::vector<Widget> children_;
};

} // namespace vkad

#endif // !VKAD_UI_UI_H_
