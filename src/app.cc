#include "app.h"
#include "gpu/pipeline.h"
#include "renderer.h"
#include "util/assert.h"
#include "window/keys.h" // IWYU pragma: export

using namespace vkad;

App::App()
    : vk_instance_(Window::vulkan_extensions()),
      window_(vk_instance_, "vkad"),
      renderer_(vk_instance_, window_.surface(), window_.width(), window_.height()),
      last_width_(window_.width()),
      last_height_(window_.height()),
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

   window_.set_capture_mouse(true);
}

App::~App() {
   FMOD_System_Release(sound_system_);
}

bool App::poll() {
   last_width_ = window_.width();
   last_height_ = window_.height();

   if (!window_.poll()) {
      return false;
   }

   int width = window_.width();
   int height = window_.height();
   bool window_resized = last_width_ != width || last_height_ != height;
   if (window_resized) {
      renderer_.recreate_swapchain(width, height, window_.surface());
   }

   if (window_.is_key_down(VKAD_KEY_ESC)) {
      window_.request_close();
   }

   Clock::time_point now = Clock::now();
   delta_ = now - last_frame_time_;
   last_frame_time_ = now;

   was_left_clicking_ = left_clicking();

   if (FMOD_System_Update(sound_system_) != FMOD_OK) {
      throw std::runtime_error("failed to poll fmod system");
   }

   player_.update(delta_.count());

   return true;
}

void App::begin_draw(Pipeline &pipeline) {
   bool did_begin = renderer_.begin_draw(pipeline);

   if (!did_begin) {
      renderer_.recreate_swapchain(window_.width(), window_.height(), window_.surface());

      VKAD_ASSERT(
          renderer_.begin_draw(pipeline), "failed to acquire next image after recreating swapchain"
      );
   }
}
