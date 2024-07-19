#include "app.h"
#include "gpu/buffer.h"
#include "math/attributes.h"
#include "math/mat4.h"
#include "math/vec2.h"
#include "renderer.h"
#include "ui/ui.h"
#include "util/assert.h"
#include "util/memory.h"
#include "window/keys.h" // IWYU pragma: export

using namespace vkad;

App::App()
    : vk_instance_(Window::vulkan_extensions()),
      window_(vk_instance_, "vkad"),
      renderer_(vk_instance_, window_.surface(), window_.width(), window_.height()),
      last_width_(window_.width()),
      last_height_(window_.height()),
      was_left_clicking_(false),
      last_frame_time_(Clock::now()),
      delta_(0),
      player_(*this),

      font_(renderer_.create_font("res/arial.ttf")),
      ui_uniforms_(renderer_.create_uniform_buffer<UiVertex>(3)),
      ui_descriptor_pool_(renderer_.create_descriptor_pool()),
      ui_descriptor_set_(
          ui_descriptor_pool_.allocate(ui_uniforms_, font_.image(), renderer_.image_sampler())
      ),
      ui_pipeline_(renderer_.create_pipeline<UiVertex>(ui_descriptor_pool_)) {

   if (FMOD_System_Create(&sound_system_, FMOD_VERSION) != FMOD_OK) {
      throw std::runtime_error("failed to create sound system");
   }

   if (FMOD_System_Init(sound_system_, 32, FMOD_INIT_NORMAL, nullptr) != FMOD_OK) {
      throw std::runtime_error("failed to initialize sound system");
   }

   window_.set_capture_mouse(true);

   Mat4 mvp = perspective_matrix() * player_.view_matrix();
   UiUniform u = {mvp, Vec3(1.0, 1.0, 1.0)};
   ui_uniforms_.upload_memory(&u, sizeof(UiUniform), 0);

   text_meshes_.emplace_back(std::move(renderer_.create_text(font_, "test")));
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

   Mat4 mvp = perspective_matrix() * player_.view_matrix();
   UiUniform u = {mvp, Vec3(1.0, 1.0, 1.0)};
   ui_uniforms_.upload_memory(&u, sizeof(UiUniform), 0);

   player_.update(delta_.count());

   return true;
}

void App::draw() {
   bool did_begin = renderer_.begin_draw(ui_pipeline_);

   if (!did_begin) {
      renderer_.recreate_swapchain(window_.width(), window_.height(), window_.surface());

      VKAD_ASSERT(
          renderer_.begin_draw(ui_pipeline_),
          "failed to acquire next image after recreating swapchain"
      );
   }

   renderer_.set_uniform(ui_pipeline_, ui_descriptor_set_, 0 * ui_uniforms_.element_size());

   for (const VertexIndexBuffer &buf : text_meshes_) {
      renderer_.draw(buf);
   }
   renderer_.end_draw();
}
