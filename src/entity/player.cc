#include "player.h"

#include <cmath>

#include "math/vec2.h"
#include "renderer.h"
#include "window/keys.h" // IWYU pragma: export

using namespace vkad;

Player::Player(Renderer &renderer) : renderer_(renderer), pos_(0, 0, 1), pitch_(0), yaw_(0) {}

void Player::update(float delta) {
   Vec2 input;

   if (renderer_.is_key_down(VKAD_KEY_D)) {
      input.x += 1;
   }

   if (renderer_.is_key_down(VKAD_KEY_A)) {
      input.x -= 1;
   }

   if (renderer_.is_key_down(VKAD_KEY_W)) {
      input.y += 1;
   }

   if (renderer_.is_key_down(VKAD_KEY_S)) {
      input.y -= 1;
   }

   if (renderer_.is_key_down(VKAD_KEY_SPACE)) {
      pos_.y += delta;
   }

   if (renderer_.is_key_down(VKAD_KEY_SHIFT)) {
      pos_.y -= delta;
   }

   float delta_yaw = renderer_.delta_mouse_x() / 2.0f;
   yaw_ -= delta_yaw * delta;

   float delta_pitch = renderer_.delta_mouse_y() / 2.0f;
   pitch_ -= delta_pitch * delta;

   if (input == Vec2(0, 0)) {
      return;
   }

   float angle = atan2f(-input.y, input.x) - yaw_;
   Vec2 move = Vec2(cosf(angle), sinf(angle)) * delta;
   pos_.x += move.x;
   pos_.z += move.y;
}
