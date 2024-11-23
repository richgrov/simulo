#ifndef VKAD_SCENE_H_
#define VKAD_SCENE_H_

#include <cstdint>

#include "renderer.h"

namespace vkad {

struct Pipelines {
   uint16_t ui;
   uint16_t mesh;
};

class SceneGraph {
public:
   SceneGraph(Renderer &renderer);

   const Pipelines &pipelines() {
      return pipelines_;
   };

private:
   Renderer &renderer_;
   Pipelines pipelines_{};
};

} // namespace vkad

#endif // !VKAD_SCENE_H_
