#ifndef VKAD_UI_UI_H_
#define VKAD_UI_UI_H_

#include <string>
#include <unordered_map>
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
   RenderMesh get_or_create_text_mesh(const std::string &text);
   void unref_text_mesh(const std::string &text);

   Renderer &renderer_;
   RenderMaterial white_text_;
   Font font_;

   struct TextMesh {
      RenderMesh mesh;
      int refcount;
   };

   std::unordered_map<std::string, TextMesh> text_meshes_;
   std::vector<Text> children_;
};

} // namespace vkad

#endif // !VKAD_UI_UI_H_
