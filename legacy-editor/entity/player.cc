#include "player.h"

#include <algorithm>
#include <cmath>
#include <numbers>

#include "app.h"
#include "math/vector.h"
#include "window/keys.h"

using namespace simulo;

Player::Player(App &app) : app_(app), pos_{0, 1, 0}, pitch_(0), yaw_(0) {}

void Player::update(float delta) {
   Vec2 input;

   if (app_.is_key_down(VKAD_KEY_D)) {
      input.x() += 1;
   }

   if (app_.is_key_down(VKAD_KEY_A)) {
      input.x() -= 1;
   }

   if (app_.is_key_down(VKAD_KEY_S)) {
      input.y() += 1;
   }

   if (app_.is_key_down(VKAD_KEY_W)) {
      input.y() -= 1;
   }

   if (app_.is_key_down(VKAD_KEY_SPACE)) {
      pos_.y() += delta;
   }

   if (app_.is_key_down(VKAD_KEY_SHIFT)) {
      pos_.y() -= delta;
   }

   float delta_yaw = app_.delta_mouse_x() / 2.0f;
   yaw_ -= delta_yaw * delta;

   float delta_pitch = app_.delta_mouse_y() / 2.0f;
   auto pi = static_cast<float>(std::numbers::pi);
   pitch_ = std::clamp(pitch_ - delta_pitch * delta, -pi / 2, pi / 2);

   if (input == Vec2{0, 0}) {
      return;
   }

   float angle = atan2f(-input.y(), input.x()) + yaw_;
   Vec2 move = Vec2{cosf(angle), sinf(angle)} * delta;
   pos_.x() += move.x();
   pos_.z() += move.y();
}
