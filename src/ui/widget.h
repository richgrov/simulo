#ifndef VKAD_UI_TEXT_H_
#define VKAD_UI_TEXT_H_

#include "gpu/buffer.h"
#include "mesh.h"
#include "ui/ui.h"
namespace vkad {

class Widget : public Mesh<UiVertex> {
public:
   Widget(std::vector<UiVertex> &&vertices, std::vector<VertexIndexBuffer::IndexType> &&indices)
       : Mesh(std::move(vertices), std::move(indices)) {}

   void set_position(int x, int y) {
      x_ = x;
      y_ = y;
   }

   Mat4 model_matrix() const {
      return Mat4::translate(Vec3(x_, y_, 0));
   }

private:
   int x_;
   int y_;
};

} // namespace vkad

#endif // !VKAD_UI_TEXT_H_
