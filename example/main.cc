#include <array>
#include <exception>
#include <iostream>
#include <stdexcept>
#include <vector>

#include <vulkan/vulkan_core.h>

#include "game.h"
#include "gpu/buffer.h"
#include "math/attributes.h"
#include "math/mat4.h"
#include "math/vec2.h"
#include "math/vec3.h"
#include "sound.h"
#include "util/memory.h"
#include "vendor/stb_image.h"
#include "window/keys.h" // IWYU pragma: export

using namespace villa;

struct Vertex {
   Vec2 pos;
   Vec2 tex_coord;

   static constexpr std::array<VertexAttribute, 2> attributes{
       VertexAttribute::vec2(),
       VertexAttribute::vec2(),
   };
};

struct ParticleUniform {
   Mat4 mvp;
   Vec3 color;
};

class Instrument {
public:
   Instrument(int index, Game &game, uint8_t key_code, Sound &sound)
       : pos_(pos_in_row_of_3(index, game.width(), game.height())), key_code_(key_code),
         prev_key_state_(game.is_key_down(key_code)), sound_(sound) {}

   bool update(Game &game) {
      bool pressed = game.is_key_down(key_code_);
      if (pressed == prev_key_state_) {
         return false;
      }

      if (pressed) {
         sound_.play();
      }

      prev_key_state_ = pressed;
      return true;
   }

   ParticleUniform uniform(Game &game) {
      Mat4 model = Mat4::translate(Vec3(pos_.x, pos_.y, 0)) * Mat4::scale(Vec3(250, 250, 1));
      Mat4 proj = Mat4::ortho(0, (float)game.width(), (float)game.height(), 0, -1, 1);
      Mat4 mvp = proj * model;

      return {
          .mvp = mvp,
          .color = prev_key_state_ ? Vec3(0.5, 0.5, 0.5) : Vec3(1.0, 1.0, 1.0),
      };
   }

   static Vec2 pos_in_row_of_3(int index, float width, float height) {
      return {width / 4.0f * (index + 1), height / 2.0f};
   }

private:
   Vec2 pos_;
   float scale_;
   uint8_t key_code_;
   bool prev_key_state_;
   Sound &sound_;
};

int main(int argc, char **argv) {
   try {
      int width, height, channels;
      stbi_uc *img_data = stbi_load("res/snare.png", &width, &height, &channels, 4);
      if (img_data == nullptr) {
         throw std::runtime_error("failed to open image");
      }

      Game game("villa");

      auto staging_buffer = game.create_staging_buffer(width * height * channels);

      auto uniform_buffer = game.create_uniform_buffer<ParticleUniform>(3);
      auto descriptor_pool = game.create_descriptor_pool();

      auto image = game.create_image(static_cast<uint32_t>(width), static_cast<uint32_t>(height));

      staging_buffer.upload_raw(img_data, width * height * channels);
      game.begin_preframe();
      game.transfer_image_layout(image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
      game.upload_texture(staging_buffer, image);
      game.transfer_image_layout(image, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
      game.end_preframe();

      image.init_view();
      auto descriptor_set = descriptor_pool.allocate(uniform_buffer, image, game.image_sampler());
      auto pipeline = game.create_pipeline<Vertex>(descriptor_pool);

      Vertex vertices[] = {
          {{0.0f, 0.0f}, {0.0, 0.0}},
          {{1.0f, 0.0f}, {1.0, 0.0}},
          {{1.0f, 1.0f}, {1.0, 1.0}},
          {{0.0f, 1.0f}, {0.0, 1.0}},
      };
      VertexIndexBuffer::IndexType indices[] = {0, 2, 1, 0, 3, 2};

      std::vector<Instrument> instruments;

      Sound bass = game.create_sound("res/sfx/bass.wav");
      Sound snare = game.create_sound("res/sfx/snare.wav");
      Sound hat = game.create_sound("res/sfx/open-hat.wav");

      instruments.emplace_back(0, game, VILLA_KEY_Q, bass);
      instruments.emplace_back(1, game, VILLA_KEY_W, snare);
      instruments.emplace_back(2, game, VILLA_KEY_E, hat);

      for (int i = 0; i < instruments.size(); ++i) {
         ParticleUniform uniform = instruments[i].uniform(game);
         uniform_buffer.upload_memory(&uniform, sizeof(ParticleUniform), i);
      }

      auto mesh_buffer = game.create_vertex_index_buffer<Vertex>(4, 6);
      staging_buffer.upload_mesh(vertices, sizeof(vertices), indices, VILLA_ARRAY_LEN(indices));

      game.begin_preframe();
      game.buffer_copy(staging_buffer, mesh_buffer);
      game.end_preframe();

      while (game.poll()) {
         float delta = game.delta();

         for (int i = 0; i < instruments.size(); ++i) {
            Instrument &instr = instruments[i];
            bool needs_uniform_update = instr.update(game);

            if (needs_uniform_update) {
               ParticleUniform uniform = instr.uniform(game);
               uniform_buffer.upload_memory(&uniform, sizeof(ParticleUniform), i);
            }
         }

         if (game.begin_draw(pipeline)) {
            for (int i = 0; i < instruments.size(); ++i) {
               game.set_uniform(pipeline, descriptor_set, i * uniform_buffer.element_size());
               game.draw(mesh_buffer);
            }
            game.end_draw();
         }

         game.wait_idle();
      }
   } catch (const std::exception &e) {
      std::cerr << "Unhandled exception: " << e.what() << "\n";
   }

   return 0;
}
