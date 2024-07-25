#include "app.h"
#include "geometry/circle.h"
#include "geometry/geometry.h"
#include "geometry/model.h"
#include "gpu/buffer.h"
#include "gpu/descriptor_pool.h"
#include "math/mat4.h"
#include "mesh.h"
#include "renderer.h"
#include "ui/ui.h"
#include "ui/widget.h"
#include "util/assert.h"
#include "window/keys.h" // IWYU pragma: export
#include <exception>
#include <string>

using namespace vkad;

enum class vkad::State {
   STANDBY,
   CREATE_POLYGON_DEGREE,
   CREATE_POLYGON_RADIUS,
};

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
      state_(State::STANDBY),

      font_("res/arial.ttf", 64, renderer_.physical_device(), renderer_.device().handle()),
      ui_uniforms_(renderer_.create_uniform_buffer<UiUniform>(3)),
      ui_material_(renderer_.create_material<UiVertex>(
          {"text-vert.spv", "text-frag.spv"},
          {
              DescriptorPool::uniform_buffer_dynamic(0),
              DescriptorPool::combined_image_sampler(1),
          }
      )),

      model_uniforms_(renderer_.create_uniform_buffer<ModelVertex>(1)),
      model_material_(renderer_.create_material<ModelVertex>(
          {"model-vert.spv", "model-frag.spv"}, {DescriptorPool::uniform_buffer_dynamic(0)}
      )) {

   renderer_.init_image(font_.image(), font_.image_data(), Font::BITMAP_WIDTH * Font::BITMAP_WIDTH);

   renderer_.link_material(
       ui_material_,
       {
           DescriptorPool::write_uniform_buffer_dynamic(ui_uniforms_),
           DescriptorPool::write_combined_image_sampler(renderer_.image_sampler(), font_.image()),
       }
   );

   renderer_.link_material(
       model_material_,
       {
           DescriptorPool::write_uniform_buffer_dynamic(model_uniforms_),
       }
   );

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

   Widget text = font_.create_text("C - Create polygon\nE - Extrude\nP - Export");
   text.set_position(30, 100);
   text.set_size(35);
   renderer_.init_mesh<UiVertex>(text);
   text_meshes_.emplace_back(std::move(text));

   Circle circle(2.0, 20);
   Model mesh = circle.extrude(1);
   renderer_.init_mesh(mesh);
   models_.push_back(mesh.id());
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

   bool window_resized = last_width_ != window_.width() || last_height_ != window_.height();
   if (window_resized) {
      handle_resize();
   }

   if (window_.is_key_down(VKAD_KEY_ESC)) {
      window_.request_close();
   }

   switch (state_) {
   case State::STANDBY:
      if (window_.key_just_pressed(VKAD_KEY_C)) {
         state_ = State::CREATE_POLYGON_DEGREE;
         add_prompt_text("Enter number of sides: ");
      }
      break;

   case State::CREATE_POLYGON_DEGREE:
      if (process_input("Enter number of sides: ")) {
         try {
            create_sides_ = std::stoi(input_);
            input_.clear();

            if (create_sides_ < 3) {
               throw std::runtime_error("need at least 3 sides");
            }
            state_ = State::STANDBY;
         } catch (const std::exception &e) {
            state_ = State::STANDBY;
         }
      }
      break;

   default:
      break;
   }

   Clock::time_point now = Clock::now();
   delta_ = now - last_frame_time_;
   last_frame_time_ = now;

   was_left_clicking_ = left_clicking();

   if (FMOD_System_Update(sound_system_) != FMOD_OK) {
      throw std::runtime_error("failed to poll fmod system");
   }

   for (int i = 0; i < text_meshes_.size(); ++i) {
      UiUniform u = {
          .mvp = ortho_matrix() * text_meshes_[i].model_matrix(),
          .color = Vec3(1.0, 1.0, 1.0),
      };
      ui_uniforms_.upload_memory(&u, sizeof(UiUniform), i);
   }

   ModelUniform u2 = {
       .mvp = perspective_matrix() * player_.view_matrix(),
       .color = Vec3(0.8, 0.2, 0.2),
   };
   model_uniforms_.upload_memory(&u2, sizeof(u2), 0);

   player_.update(delta_.count());

   return true;
}

void App::draw() {
   bool did_begin = renderer_.begin_draw();

   if (!did_begin) {
      renderer_.recreate_swapchain(window_.width(), window_.height(), window_.surface());

      VKAD_ASSERT(
          renderer_.begin_draw(), "failed to acquire next image after recreating swapchain"
      );
   }

   renderer_.set_material(model_material_);
   renderer_.set_uniform(model_material_, 0);

   for (const int id : models_) {
      renderer_.draw(id);
   }

   renderer_.set_material(ui_material_);

   for (int i = 0; i < text_meshes_.size(); ++i) {
      Widget &widget = text_meshes_[i];
      renderer_.set_uniform(ui_material_, i * ui_uniforms_.element_size());
      renderer_.draw(widget.id());
   }

   renderer_.end_draw();
}

void App::handle_resize() {
   int width = window_.width();
   int height = window_.height();
   renderer_.recreate_swapchain(width, height, window_.surface());
}

bool App::process_input(const std::string &message) {
   if (window_.typed_chars().empty()) {
      return false;
   }

   if (text_meshes_.size() >= 2) {
      renderer_.delete_mesh(text_meshes_[1]);
      text_meshes_.erase(text_meshes_.begin() + 1);
   }

   for (char c : window_.typed_chars()) {
      switch (c) {
      case '\b':
         if (!input_.empty()) {
            input_.pop_back();
         }
         break;

      case '\r':
         return true;

      default:
         input_.push_back(c);
         break;
      }
   }

   add_prompt_text(message);
   return false;
}

void App::add_prompt_text(const std::string &message) {
   Widget text = font_.create_text(message + input_);
   text.set_position(30, window_.height() - 50);
   text.set_size(35);
   renderer_.init_mesh(text);
   text_meshes_.emplace_back(std::move(text));
}
