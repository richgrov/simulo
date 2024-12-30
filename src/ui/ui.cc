#include "ui.h"

#include <utility>

#include "render/renderer.h"
#include "res/arial.ttf.h"
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
   RenderMesh mesh = get_or_create_text_mesh(text.text());
   text.set_position(30, 100);
   text.set_size(text.font_size());
   text.renderer_handle_ = renderer_.add_object(mesh, text.transform(), white_text_);
   children_.emplace_back(std::move(text));
}

void Ui::delete_child(int index) {
   VKAD_DEBUG_ASSERT(index >= 0 && index < children_.size(), "invalid child index {}", index);

   Text &text = children_[index];
   renderer_.delete_object(text.renderer_handle_);
   unref_text_mesh(text.text());
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

void Ui::unref_text_mesh(const std::string &text) {
   VKAD_DEBUG_ASSERT(
       text_meshes_.contains(text), "tried to delete non-existent mesh for text '{}'", text
   );

   TextMesh &mesh = text_meshes_.at(text);
   if (--mesh.refcount == 0) {
      renderer_.delete_mesh(mesh.mesh);
   }
}
