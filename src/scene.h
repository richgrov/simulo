#ifndef VKAD_SCENE_H_
#define VKAD_SCENE_H_

#include <cstdint>

#include "renderer.h"

namespace vkad {

struct Materials {
   uint16_t ui;
   uint16_t mesh;
};

class SceneGraph {
public:
   SceneGraph(Renderer &renderer);

   const Materials &materials() {
      return materials_;
   };

private:
   Renderer &renderer_;
   Materials materials_{};
};

} // namespace vkad

#endif // !VKAD_SCENE_H_
