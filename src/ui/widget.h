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
};

} // namespace vkad

#endif // !VKAD_UI_TEXT_H_
