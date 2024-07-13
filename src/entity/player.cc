#include "player.h"

#include <cmath>

#include "game.h"
#include "math/vec2.h"
#include "window/keys.h" // IWYU pragma: export

using namespace villa;

Player::Player(Game &game) : game_(game), pos_(0, 0, 1), pitch_(0), yaw_(0) {}

void Player::update(float delta) {
   Vec2 input;

   if (game_.is_key_down(VILLA_KEY_D)) {
      input.x += 1;
   }

   if (game_.is_key_down(VILLA_KEY_A)) {
      input.x -= 1;
   }

   if (game_.is_key_down(VILLA_KEY_W)) {
      input.y += 1;
   }

   if (game_.is_key_down(VILLA_KEY_S)) {
      input.y -= 1;
   }

   float delta_yaw = game_.delta_mouse_x() / 2.0f;
   yaw_ -= delta_yaw * delta;

   float delta_pitch = game_.delta_mouse_y() / 2.0f;
   pitch_ -= delta_pitch * delta;

   if (input == Vec2(0, 0)) {
      return;
   }

   float angle = atan2f(-input.y, input.x) - yaw_;
   Vec2 move = Vec2(cosf(angle), sinf(angle)) * delta;
   pos_.x += move.x;
   pos_.z += move.y;
}
