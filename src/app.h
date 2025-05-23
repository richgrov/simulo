#pragma once

#include <chrono>
#include <memory>

#include "entity/player.h"
#include "geometry/model.h"
#include "geometry/shape.h"
#include "gpu/gpu.h"
#include "math/angle.h"
#include "math/matrix.h"
#include "render/renderer.h"
#include "ui/font.h"
#include "ui/ui.h"
#include "window/window.h" // IWYU pragma: export

namespace simulo {

enum class State;

class App {
   using Clock = std::chrono::high_resolution_clock;

public:
   App();

   ~App();

   bool poll();

   void draw();

   inline Renderer &renderer() {
      return renderer_;
   }

   inline int width() const {
      return window_->width();
   }

   inline int height() const {
      return window_->height();
   }

   inline int mouse_x() const {
      return window_->mouse_x();
   }

   inline int mouse_y() const {
      return window_->mouse_y();
   }

   inline int delta_mouse_x() const {
      return window_->delta_mouse_x();
   }

   inline int delta_mouse_y() const {
      return window_->delta_mouse_y();
   }

   inline bool left_clicking() const {
      return window_->left_clicking();
   }

   inline bool left_clicked_now() const {
      return !was_left_clicking_ && left_clicking();
   }

   inline bool is_key_down(uint8_t key_code) const {
      return window_->is_key_down(key_code);
   }

   inline float delta() const {
      return delta_.count();
   }

   inline Player &player() {
      return player_;
   }

   inline Mat4 ortho_matrix() const {
      return Mat4::ortho(window_->width(), window_->height(), -1, 1);
   }

   inline Mat4 perspective_matrix() const {
      float aspect = static_cast<float>(window_->width()) / static_cast<float>(window_->height());
      return Mat4::perspective(aspect, deg_to_rad(70), 0.01, 100);
   }

private:
   void handle_resize();
   bool process_input(const std::string &message);
   void add_prompt_text(const std::string &message);

   Gpu gpu_;
   std::unique_ptr<Window> window_;
   Renderer renderer_;

   RenderMaterial blue_mesh_;

   std::vector<Shape> shapes_;
   std::vector<Model> models_;

   int last_width_;
   int last_height_;

   Clock::time_point last_frame_time_;
   std::chrono::duration<float> delta_;
   bool was_left_clicking_;

   Ui ui_;
   Player player_;
   State state_;
   std::string input_;
   int create_sides_;
   float create_radius_;
   float extrude_amount_;
};

} // namespace simulo
