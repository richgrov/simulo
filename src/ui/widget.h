#ifndef VKAD_UI_TEXT_H_
#define VKAD_UI_TEXT_H_

#include "gpu/vulkan/buffer.h"
#include "mesh.h"
#include "render/ui.h"
namespace vkad {

class Widget : public Mesh<UiVertex> {
public:
   Widget(std::vector<UiVertex> &&vertices, std::vector<VertexIndexBuffer::IndexType> &&indices)
       : Mesh(std::move(vertices), std::move(indices)) {}

   inline void set_position(int x, int y) {
      x_ = x;
      y_ = y;
   }

   inline void set_size(int size) {
      scale_ = size;
   }

   inline Mat4 model_matrix() const {
      return Mat4::translate(Vec3(x_, y_, 0)) * Mat4::scale(Vec3(scale_, scale_, 1));
   }

private:
   int x_;
   int y_;
   int scale_;
};

} // namespace vkad

#endif // !VKAD_UI_TEXT_H_
