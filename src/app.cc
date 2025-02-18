#include "app.h"
#include "geometry/circle.h"
#include "geometry/model.h"
#include "math/mat4.h"
#include "mesh.h"
#include "render/model.h"
#include "render/renderer.h"
#include "render/ui.h"
#include "stl.h"
#include "ui/text.h"
#include "util/assert.h"
#include "window/keys.h"

#include <exception>
#include <fstream>
#include <memory>
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
#ifndef __APPLE__
    : vk_instance_(Window::vulkan_extensions()),
      window_(create_window(vk_instance_, "vkad")),
      renderer_(vk_instance_, window_->surface(), window_->width(), window_->height()),
#else
    : window_(create_window(gpu_, "vkad")),
      renderer_(gpu_, window_->layer_pixel_format(), window_->metal_layer()),
#endif
      last_width_(window_->width()),
      last_height_(window_->height()),
      was_left_clicking_(false),
      last_frame_time_(Clock::now()),
      delta_(0),
      ui_(renderer_),
      player_(*this),
      state_(State::STANDBY) {

   blue_mesh_ = renderer_.create_material<ModelUniform>(
       renderer_.pipelines().mesh,
       {
           {"color", Vec3{0.1, 0.1, 0.8}},
       }
   );

   window_->set_capture_mouse(true);

   auto text = std::make_unique<Text>("C - Create polygon\nE - Extrude\nP - Export", 35);
   text->set_position(30, 100);
   text->set_size(text->font_size());
   ui_.add_child(std::move(text));
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
            Model mesh(circle.to_model());
            mesh.mesh_handle_ = renderer_.create_mesh(mesh.vertex_data(), mesh.indices());
            mesh.renderer_handle_ =
                renderer_.add_object(mesh.mesh_handle_, mesh.transform(), blue_mesh_);
            models_.emplace_back(mesh);
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
               renderer_.delete_object(model.renderer_handle_);
               renderer_.delete_mesh(model.mesh_handle_);
            }
            models_.clear();

            Shape &shape = shapes_.back();
            Model mesh(shape.extrude(extrude_amount_));
            mesh.mesh_handle_ = renderer_.create_mesh(mesh.vertex_data(), mesh.indices());
            mesh.renderer_handle_ =
                renderer_.add_object(mesh.mesh_handle_, mesh.transform(), blue_mesh_);
            models_.emplace_back(mesh);
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

   player_.update(delta_.count());

   return true;
}

void App::draw() {
   Mat4 ui_view_projection(ortho_matrix());
   Mat4 world_view_projection(perspective_matrix() * player_.view_matrix());

#ifndef __APPLE__
   bool swapchain_bad = !renderer_.render(ui_view_projection, world_view_projection);

   if (swapchain_bad) {
      renderer_.recreate_swapchain(window_->width(), window_->height(), window_->surface());

      VKAD_ASSERT(
          renderer_.render(ui_view_projection, world_view_projection),
          "failed to acquire next image after recreating swapchain"
      );
   }
#endif
}

void App::handle_resize() {
   int width = window_->width();
   int height = window_->height();
#ifndef __APPLE__
   renderer_.recreate_swapchain(width, height, window_->surface());
#endif
}

bool App::process_input(const std::string &message) {
   if (window_->typed_chars().empty()) {
      return false;
   }

   if (ui_.num_children() >= 2) {
      ui_.delete_child(1);
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
   auto text = std::make_unique<Text>(message + input_, 35);
   text->set_position(30, window_->height() - 50);
   text->set_size(text->font_size());
   ui_.add_child(std::move(text));
}
