#include "ui.h"

#include <utility>

#include "render/renderer.h" // IWYU pragma: export
#include "res/arial.ttf.h"
#include "ui/widget.h"
#include "util/assert.h"

using namespace vkad;

Ui::Ui(Renderer &renderer)
    : renderer_(renderer),
      font_(res_arial_ttf, 64, renderer.physical_device(), renderer.device().handle()) {

   RenderImage font_texture =
       renderer.create_image(font_.image_data(), Font::kBitmapWidth, Font::kBitmapWidth);
   font_.set_image(font_texture);

   white_text_ = renderer.create_material<UiUniform>(
       renderer.pipelines().ui,
       {
           {"image", font_.image()},
           {"color", Vec3(1.0, 1.0, 1.0)},
       }
   );
}

void Ui::add_child(Text &&text) {
   Widget widget(font_.create_text(text.text()));
   widget.set_position(30, 100);
   widget.set_size(text.font_size());
   widget.mesh_handle_ = renderer_.create_mesh(widget.vertex_data(), widget.indices());
   widget.renderer_handle_ =
       renderer_.add_object(widget.mesh_handle_, widget.transform(), white_text_);
   children_.emplace_back(std::move(widget));
}

void Ui::delete_child(int index) {
   VKAD_DEBUG_ASSERT(index >= 0 && index < children_.size(), "invalid child index {}", index);

   Widget &widget = children_[index];
   renderer_.delete_object(widget.renderer_handle_);
   renderer_.delete_mesh(widget.mesh_handle_);
   children_.erase(children_.begin() + index);
}
