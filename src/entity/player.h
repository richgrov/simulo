#pragma once

#include "math/matrix.h"
#include "math/vector.h"

namespace vkad {

class App;

class Player {
public:
   explicit Player(App &app);

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
   App &app_;

   Vec3 pos_;
   float yaw_;
   float pitch_;
};

} // namespace vkad
