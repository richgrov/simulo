#ifndef VKAD_ENTITY_PLAYER_H_
#define VKAD_ENTITY_PLAYER_H_

#include "math/mat4.h"
#include "math/vec3.h"

namespace vkad {

class Renderer;

class Player {
public:
   explicit Player(Renderer &renderer);

   inline Vec3 pos() const {
      return pos_;
   }

   inline float yaw() const {
      return yaw_;
   }

   inline float pitch() const {
      return pitch_;
   }

   inline Mat4 view_matrix() const {
      return Mat4::rotate_x(-pitch_) * Mat4::rotate_y(-yaw_) * Mat4::translate(-pos_);
   }

   void update(float delta);

private:
   Renderer &renderer_;

   Vec3 pos_;
   float yaw_;
   float pitch_;
};

} // namespace vkad

#endif // !VKAD_ENTITY_PLAYER_H_
