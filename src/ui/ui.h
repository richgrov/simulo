#ifndef VKAD_UI_UI_H_
#define VKAD_UI_UI_H_

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include "render/renderer.h"
#include "ui/font.h"
#include "ui/text.h"
#include "ui/widget.h"

namespace vkad {

class Ui : WidgetVisitor {
public:
   Ui(Renderer &renderer);

   void add_child(std::unique_ptr<Widget> &&widget);

   int num_children() const {
      return children_.size();
   }

   void delete_child(int index);

private:
   RenderMesh get_or_create_text_mesh(const std::string &text);

   virtual void on_init_text(Text &text) override;
   virtual void on_delete_text(Text &text) override;

   Renderer &renderer_;
   RenderMaterial white_text_;
   Font font_;

   struct TextMesh {
      RenderMesh mesh;
      int refcount;
   };

   std::unordered_map<std::string, TextMesh> text_meshes_;
   std::vector<std::unique_ptr<Widget>> children_;
};

} // namespace vkad

#endif // !VKAD_UI_UI_H_
