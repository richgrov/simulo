#include <array>
#include <cmath>
#include <exception>
#include <iostream>
#include <numbers>
#include <vector>

#include <vulkan/vulkan_core.h>

#include "game.h"
#include "gpu/buffer.h"
#include "math/attributes.h"
#include "math/mat4.h"
#include "math/vec2.h"
#include "math/vec3.h"
#include "util/memory.h"
#include "util/rand.h"
#include "vendor/stb_image.h"

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

class Particle {
public:
   Particle(float x, float y, Vec3 color) : pos_(x, y), color_(color), lifespan_(randf() * 4) {
      float angle = randf() * std::numbers::pi_v<float> * 2;
      float magnitude = randf();
      velocity_ = {cosf(angle) * magnitude, sinf(angle) * magnitude};
   }

   void update(float delta) {
      velocity_.y += 0.5 * delta;
      pos_ += velocity_ * delta;
      lifespan_ -= 0.01;

      if (lifespan_ < 0.05) {
         color_ = {1.0, 1.0, 1.0};
      }
   }

   Vec2 pos() const {
      return pos_;
   }

   Vec3 color() const {
      return color_;
   }

   float lifespan() const {
      return lifespan_;
   }

private:
   Vec2 pos_;
   Vec3 color_;
   Vec2 velocity_;
   float lifespan_;
};

int main(int argc, char **argv) {
   try {
      int width, height, channels;
      stbi_uc *img_data = stbi_load("res/background.png", &width, &height, &channels, 4);
      if (img_data == nullptr) {
         throw std::runtime_error("failed to open image");
      }

      Game game("villa");

      auto staging_buffer = game.create_staging_buffer(width * height * channels);

      auto uniform_buffer = game.create_uniform_buffer<ParticleUniform>(512);
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
          {{-0.05f, -0.05f}, {1.0, 0.0}},
          {{0.05f, -0.05f}, {0.0, 0.0}},
          {{0.05f, 0.05f}, {0.0, 1.0}},
          {{-0.05f, 0.05f}, {1.0, 1.0}},
      };
      VertexIndexBuffer::IndexType indices[] = {0, 1, 2, 0, 2, 3};

      std::vector<Particle> particles;

      auto mesh_buffer = game.create_vertex_index_buffer<Vertex>(4, 6);
      staging_buffer.upload_mesh(vertices, sizeof(vertices), indices, VILLA_ARRAY_LEN(indices));

      game.begin_preframe();
      game.buffer_copy(staging_buffer, mesh_buffer);
      game.end_preframe();

      while (game.poll()) {
         float delta = game.delta();

         if (game.left_clicked_now()) {
            float mouse_x = static_cast<float>(game.mouse_x());
            float mouse_y = static_cast<float>(game.mouse_y());

            float norm_x = mouse_x / game.width() * 2.f - 1.f;
            float norm_y = mouse_y / game.height() * 2.f - 1.f;

            Vec3 color = {randf(), randf(), randf()};
            for (int i = 0; i < 92; ++i) {
               particles.emplace_back(Particle(norm_x, norm_y, color));
            }
         }

         std::erase_if(particles, [](const Particle &particle) {
            return particle.lifespan() <= 0.0;
         });

         for (int i = 0; i < particles.size(); ++i) {
            Particle &particle = particles[i];
            particle.update(delta);
            Vec2 pos = particle.pos();
            ParticleUniform uniform = {Mat4::translate(Vec3(pos.x, pos.y, 0.0f)), particle.color()};
            uniform_buffer.upload_memory(&uniform, sizeof(ParticleUniform), i);
         }

         if (game.begin_draw(pipeline)) {
            for (int i = 0; i < particles.size(); ++i) {
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
