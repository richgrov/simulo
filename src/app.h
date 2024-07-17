#ifndef VKAD_APP_H_
#define VKAD_APP_H_

#include <chrono>

#include "entity/player.h"
#include "renderer.h"
#include "sound.h"
#include "ui/font.h"

namespace vkad {

class App {
   using Clock = std::chrono::high_resolution_clock;

public:
   App();

   ~App();

   bool poll();

   inline Renderer &renderer() {
      return renderer_;
   }

   inline int width() const {
      return renderer_.window().width();
   }

   inline int height() const {
      return renderer_.window().height();
   }

   inline int mouse_x() const {
      return renderer_.window().mouse_x();
   }

   inline int mouse_y() const {
      return renderer_.window().mouse_y();
   }

   inline int delta_mouse_x() const {
      return renderer_.window().delta_mouse_x();
   }

   inline int delta_mouse_y() const {
      return renderer_.window().delta_mouse_y();
   }

   inline bool left_clicking() const {
      return renderer_.window().left_clicking();
   }

   inline bool left_clicked_now() const {
      return !was_left_clicking_ && left_clicking();
   }

   inline bool is_key_down(uint8_t key_code) const {
      return renderer_.window().is_key_down(key_code);
   }

   inline float delta() const {
      return delta_.count();
   }

   inline Player &player() {
      return player_;
   }

   Sound create_sound(const char *path) {
      return Sound(sound_system_, path);
   }

private:
   Renderer renderer_;

   Font font_;
   FMOD_SYSTEM *sound_system_;

   Clock::time_point last_frame_time_;
   std::chrono::duration<float> delta_;
   bool was_left_clicking_;

   Player player_;
};

} // namespace vkad

#endif // !VKAD_APP_H_
