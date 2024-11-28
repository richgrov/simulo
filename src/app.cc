#include "app.h"
#include "geometry/circle.h"
#include "geometry/model.h"
#include "gpu/vulkan/buffer.h"
#include "gpu/vulkan/descriptor_pool.h"
#include "math/mat4.h"
#include "mesh.h"
#include "render/model.h"
#include "render/renderer.h" // IWYU pragma: export
#include "render/ui.h"
#include "res/arial.ttf.h"
#include "stl.h"
#include "ui/widget.h"
#include "util/assert.h"
#include "window/keys.h" // IWYU pragma: export
#include <exception>
#include <fstream>
#include <stdexcept>
#include <string>

using namespace vkad;

enum class vkad::State {
   STANDBY,
   CREATE_POLYGON_DEGREE,
   CREATE_POLYGON_RADIUS,
   EXTRUDE,
};

App::App()
    : vk_instance_(Window::vulkan_extensions()),
      window_(create_window(vk_instance_, "vkad")),
      renderer_(vk_instance_, window_->surface(), window_->width(), window_->height()),
      last_width_(window_->width()),
      last_height_(window_->height()),
      was_left_clicking_(false),
      last_frame_time_(Clock::now()),
      delta_(0),
      player_(*this),
      state_(State::STANDBY),

      font_(res_arial_ttf, 64, renderer_.physical_device(), renderer_.device().handle()),
      ui_uniforms_(renderer_.create_uniform_buffer<UiUniform>(3)),

      model_uniforms_(renderer_.create_uniform_buffer<ModelVertex>(1)) {

   renderer_.init_image(font_.image(), font_.image_data(), Font::kBitmapWidth * Font::kBitmapWidth);

   renderer_.link_material(
       renderer_.pipelines().ui,
       {
           DescriptorPool::write_uniform_buffer_dynamic(ui_uniforms_),
           DescriptorPool::write_combined_image_sampler(renderer_.image_sampler(), font_.image()),
       }
   );

   renderer_.link_material(
       renderer_.pipelines().mesh,
       {
           DescriptorPool::write_uniform_buffer_dynamic(model_uniforms_),
       }
   );

   window_->set_capture_mouse(true);

   Mat4 mvp = perspective_matrix() * player_.view_matrix();
   UiUniform u = {mvp, Vec3(1.0, 1.0, 1.0)};
   ui_uniforms_.upload_memory(&u, sizeof(UiUniform), 0);

   Widget text = font_.create_text("C - Create polygon\nE - Extrude\nP - Export");
   text.set_position(30, 100);
   text.set_size(35);
   renderer_.init_mesh<UiVertex>(text);
   text_meshes_.emplace_back(std::move(text));
}

App::~App() {}

bool App::poll() {
   last_width_ = window_->width();
   last_height_ = window_->height();

   if (!window_->poll()) {
      return false;
   }

   bool window_resized = last_width_ != window_->width() || last_height_ != window_->height();
   if (window_resized) {
      handle_resize();
   }

   if (window_->is_key_down(VKAD_KEY_ESC)) {
      window_->request_close();
   }

   switch (state_) {
   case State::STANDBY:
      if (window_->key_just_pressed(VKAD_KEY_C)) {
         state_ = State::CREATE_POLYGON_DEGREE;
         add_prompt_text("Enter number of sides: ");
      } else if (window_->key_just_pressed(VKAD_KEY_E)) {
         state_ = State::EXTRUDE;
         add_prompt_text("Extrude: ");
      } else if (window_->key_just_pressed(VKAD_KEY_P)) {
         std::vector<Triangle> tris = models_[0].to_stl_triangles();
         std::ofstream file("model.stl");
         write_stl("model", tris, file);
         add_prompt_text("Model saved.");
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

            state_ = State::CREATE_POLYGON_RADIUS;
            add_prompt_text("Enter radius: ");
         } catch (const std::exception &e) {
            state_ = State::STANDBY;
         }
      }
      break;

   case State::CREATE_POLYGON_RADIUS:
      if (process_input("Enter radius: ")) {
         try {
            create_radius_ = std::stof(input_);
            input_.clear();

            if (create_radius_ <= 0) {
               throw std::runtime_error("radius must be larger than 0");
            }

            state_ = State::STANDBY;

            Circle circle(create_radius_, create_sides_);
            shapes_.push_back(circle);
            Model mesh = circle.to_model();
            renderer_.init_mesh(mesh);
            models_.emplace_back(std::move(mesh));
         } catch (const std::exception &e) {
            state_ = State::STANDBY;
         }
      }
      break;

   case State::EXTRUDE:
      if (process_input("Extrude: ")) {
         try {
            extrude_amount_ = std::stof(input_);
            input_.clear();

            if (extrude_amount_ <= 0) {
               throw std::runtime_error("must extrude by more than 0");
            }

            state_ = State::STANDBY;

            for (Model &model : models_) {
               renderer_.delete_mesh(model);
            }
            models_.clear();

            Shape &shape = shapes_.back();
            Model mesh = shape.extrude(extrude_amount_);
            renderer_.init_mesh(mesh);
            models_.emplace_back(std::move(mesh));
            shapes_.clear();
         } catch (const std::exception &e) {
            state_ = State::STANDBY;
         }
      }
      break;
   }

   Clock::time_point now = Clock::now();
   delta_ = now - last_frame_time_;
   last_frame_time_ = now;

   was_left_clicking_ = left_clicking();

   for (int i = 0; i < text_meshes_.size(); ++i) {
      UiUniform u = {
          .mvp = ortho_matrix() * text_meshes_[i].model_matrix(),
          .color = Vec3(1.0, 1.0, 1.0),
      };
      ui_uniforms_.upload_memory(&u, sizeof(UiUniform), i);
   }

   ModelUniform u2 = {
       .mvp = perspective_matrix() * player_.view_matrix(),
       .color = Vec3(0.1, 0.1, 0.8),
   };
   model_uniforms_.upload_memory(&u2, sizeof(u2), 0);

   player_.update(delta_.count());

   return true;
}

void App::draw() {
   bool did_begin = renderer_.begin_draw();

   if (!did_begin) {
      renderer_.recreate_swapchain(window_->width(), window_->height(), window_->surface());

      VKAD_ASSERT(
          renderer_.begin_draw(), "failed to acquire next image after recreating swapchain"
      );
   }

   renderer_.set_material(renderer_.pipelines().mesh);
   renderer_.set_uniform(renderer_.pipelines().mesh, 0);

   for (const Model &model : models_) {
      renderer_.draw(model.id());
   }

   renderer_.set_material(renderer_.pipelines().ui);

   for (int i = 0; i < text_meshes_.size(); ++i) {
      Widget &widget = text_meshes_[i];
      renderer_.set_uniform(renderer_.pipelines().ui, i * ui_uniforms_.element_size());
      renderer_.draw(widget.id());
   }

   renderer_.end_draw();
}

void App::handle_resize() {
   int width = window_->width();
   int height = window_->height();
   renderer_.recreate_swapchain(width, height, window_->surface());
}

bool App::process_input(const std::string &message) {
   if (window_->typed_chars().empty()) {
      return false;
   }

   if (text_meshes_.size() >= 2) {
      renderer_.delete_mesh(text_meshes_[1]);
      text_meshes_.erase(text_meshes_.begin() + 1);
   }

   for (char c : window_->typed_chars()) {
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
   text.set_position(30, window_->height() - 50);
   text.set_size(35);
   renderer_.init_mesh(text);
   text_meshes_.emplace_back(std::move(text));
}
