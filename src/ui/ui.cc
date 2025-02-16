#include "ui.h"

#include <utility>

#include "render/renderer.h"
#include "res/arial.ttf.h"
#include "util/assert.h"

using namespace vkad;

Ui::Ui(Renderer &renderer)
    : renderer_(renderer), font_(std::span(res_arial_ttf, res_arial_ttf_len), 64) {

   RenderImage font_texture =
       renderer.create_image(font_.image_data(), Font::kBitmapWidth, Font::kBitmapWidth);
   font_.set_image(font_texture);

   white_text_ = renderer.create_material<UiUniform>(
       renderer.pipelines().ui,
       {
           {"image", font_.image()},
           {"color", Vec3{1.f, 1.f, 1.f}},
       }
   );
}

void Ui::add_child(std::unique_ptr<Widget> &&widget) {
   widget->on_init(*this);
   children_.emplace_back(std::move(widget));
}

void Ui::delete_child(int index) {
   VKAD_DEBUG_ASSERT(index >= 0 && index < children_.size(), "invalid child index {}", index);
   children_[index]->on_delete(*this);
   children_.erase(children_.begin() + index);
}

RenderMesh Ui::get_or_create_text_mesh(const std::string &text) {
   if (text_meshes_.contains(text)) {
      return text_meshes_.at(text).mesh;
   }

   std::vector<UiVertex> vertices;
   std::vector<Renderer::IndexBufferType> indices;
   font_.create_text(text, vertices, indices);

   std::span<uint8_t> vertex_data(
       reinterpret_cast<uint8_t *>(vertices.data()), vertices.size() * sizeof(UiVertex)
   );

   auto [value, inserted] = text_meshes_.emplace(
       text,
       TextMesh{
           .mesh = renderer_.create_mesh(vertex_data, indices),
           .refcount = 1,
       }
   );

   VKAD_DEBUG_ASSERT(inserted, "mesh for text '{}' not inserted", text);
   return value->second.mesh;
}

void Ui::on_init_text(Text &text) {
   RenderMesh mesh = get_or_create_text_mesh(text.text());
   text.renderer_handle_ = renderer_.add_object(mesh, text.transform(), white_text_);
}

void Ui::on_delete_text(Text &text) {
   VKAD_DEBUG_ASSERT(
       text_meshes_.contains(text.text()), "tried to delete non-existent mesh for text '{}'",
       text.text()
   );

   TextMesh &mesh = text_meshes_.at(text.text());
   if (--mesh.refcount == 0) {
      renderer_.delete_mesh(mesh.mesh);
   }

   renderer_.delete_object(text.renderer_handle_);
}
