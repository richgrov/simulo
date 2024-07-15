#include <array>
#include <exception>
#include <iostream>
#include <stdexcept>

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

using namespace vkad;

struct Vertex {
   Vec3 pos;
   Vec2 tex_coord;

   static constexpr std::array<VertexAttribute, 2> attributes{
       VertexAttribute::vec3(),
       VertexAttribute::vec2(),
   };
};

struct Uniform {
   Mat4 mvp;
   Vec3 color;
};

Uniform uniform(Game &game) {
   Mat4 mvp = game.perspective_matrix() * game.player().view_matrix();
   return {mvp, Vec3(1.0, 1.0, 1.0)};
}

int main(int argc, char **argv) {
   try {
      int width, height, channels;
      stbi_uc *img_data = stbi_load("res/background.png", &width, &height, &channels, 4);
      if (img_data == nullptr) {
         throw std::runtime_error("failed to open image");
      }
      channels = 4;

      Game game("vkad");

      auto staging_buffer = game.create_staging_buffer(width * height * channels);

      auto uniform_buffer = game.create_uniform_buffer<Uniform>(3);
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
          {{0.0f, 0.0f, 0}, {0.0, 0.0}},
          {{1.0f, 0.0f, 0}, {1.0, 0.0}},
          {{1.0f, 1.0f, 0}, {1.0, 1.0}},
          {{0.0f, 1.0f, 0}, {0.0, 1.0}},
      };
      VertexIndexBuffer::IndexType indices[] = {0, 2, 1, 0, 3, 2};

      Uniform u = uniform(game);
      uniform_buffer.upload_memory(&u, sizeof(Uniform), 0);

      auto mesh_buffer = game.create_vertex_index_buffer<Vertex>(
          VKAD_ARRAY_LEN(vertices), VKAD_ARRAY_LEN(indices)
      );
      staging_buffer.upload_mesh(vertices, sizeof(vertices), indices, VKAD_ARRAY_LEN(indices));

      game.begin_preframe();
      game.buffer_copy(staging_buffer, mesh_buffer);
      game.end_preframe();

      int mouse_x = game.mouse_x();
      int mouse_y = game.mouse_y();

      while (game.poll()) {
         float delta = game.delta();

         Uniform u = uniform(game);
         uniform_buffer.upload_memory(&u, sizeof(Uniform), 0);

         if (game.begin_draw(pipeline)) {
            game.set_uniform(pipeline, descriptor_set, 0 * uniform_buffer.element_size());
            game.draw(mesh_buffer);
            game.end_draw();
         }

         game.wait_idle();
      }
   } catch (const std::exception &e) {
      std::cerr << "Unhandled exception: " << e.what() << "\n";
   }

   return 0;
}
