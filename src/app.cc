#include "app.h"
#include "renderer.h"
#include "window/keys.h" // IWYU pragma: export

using namespace vkad;

App::App()
    : renderer_("vkad"),
      was_left_clicking_(false),
      font_(renderer_.create_font("res/arial.ttf")),
      last_frame_time_(Clock::now()),
      delta_(0),
      player_(*this) {

   if (FMOD_System_Create(&sound_system_, FMOD_VERSION) != FMOD_OK) {
      throw std::runtime_error("failed to create sound system");
   }

   if (FMOD_System_Init(sound_system_, 32, FMOD_INIT_NORMAL, nullptr) != FMOD_OK) {
      throw std::runtime_error("failed to initialize sound system");
   }

   renderer_.window().set_capture_mouse(true);
}

App::~App() {
   FMOD_System_Release(sound_system_);
}

bool App::poll() {
   if (renderer_.window().is_key_down(VKAD_KEY_ESC)) {
      renderer_.window().request_close();
   }

   Clock::time_point now = Clock::now();
   delta_ = now - last_frame_time_;
   last_frame_time_ = now;

   was_left_clicking_ = left_clicking();

   if (FMOD_System_Update(sound_system_) != FMOD_OK) {
      throw std::runtime_error("failed to poll fmod system");
   }

   player_.update(delta_.count());

   return renderer_.poll();
}
