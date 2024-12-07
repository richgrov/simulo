#ifndef VKAD_RENDER_RENDER_OBJECT_H_
#define VKAD_RENDER_RENDER_OBJECT_H_

#include "math/mat4.h"

namespace vkad {

class RenderObject {
public:
   virtual Mat4 transform() const = 0;

   int mesh_;

private:
   friend class Renderer;
   int id_;
};

} // namespace vkad

#endif // !VKAD_RENDER_RENDER_OBJECT_H_
