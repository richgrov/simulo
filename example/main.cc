#include <array>
#include <exception>
#include <iostream>
#include <stdexcept>

#include <vulkan/vulkan_core.h>

#include "gpu/buffer.h"
#include "math/attributes.h"
#include "math/mat4.h"
#include "math/vec2.h"
#include "math/vec3.h"
#include "renderer.h"
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

Uniform uniform(Renderer &renderer) {
   Mat4 mvp = renderer.perspective_matrix() * renderer.player().view_matrix();
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

      Renderer renderer("vkad");

      auto staging_buffer = renderer.create_staging_buffer(width * height * channels);

      auto uniform_buffer = renderer.create_uniform_buffer<Uniform>(3);
      auto descriptor_pool = renderer.create_descriptor_pool();

      auto image =
          renderer.create_image(static_cast<uint32_t>(width), static_cast<uint32_t>(height));

      staging_buffer.upload_raw(img_data, width * height * channels);
      renderer.begin_preframe();
      renderer.transfer_image_layout(image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
      renderer.upload_texture(staging_buffer, image);
      renderer.transfer_image_layout(image, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
      renderer.end_preframe();

      image.init_view();
      auto descriptor_set =
          descriptor_pool.allocate(uniform_buffer, image, renderer.image_sampler());
      auto pipeline = renderer.create_pipeline<Vertex>(descriptor_pool);

      Vertex vertices[] = {
          {{0.0f, 0.0f, 0}, {0.0, 0.0}},
          {{1.0f, 0.0f, 0}, {1.0, 0.0}},
          {{1.0f, 1.0f, 0}, {1.0, 1.0}},
          {{0.0f, 1.0f, 0}, {0.0, 1.0}},
      };
      VertexIndexBuffer::IndexType indices[] = {0, 2, 1, 0, 3, 2};

      Uniform u = uniform(renderer);
      uniform_buffer.upload_memory(&u, sizeof(Uniform), 0);

      auto mesh_buffer = renderer.create_vertex_index_buffer<Vertex>(
          VKAD_ARRAY_LEN(vertices), VKAD_ARRAY_LEN(indices)
      );
      staging_buffer.upload_mesh(vertices, sizeof(vertices), indices, VKAD_ARRAY_LEN(indices));

      renderer.begin_preframe();
      renderer.buffer_copy(staging_buffer, mesh_buffer);
      renderer.end_preframe();

      int mouse_x = renderer.mouse_x();
      int mouse_y = renderer.mouse_y();

      while (renderer.poll()) {
         float delta = renderer.delta();

         Uniform u = uniform(renderer);
         uniform_buffer.upload_memory(&u, sizeof(Uniform), 0);

         if (renderer.begin_draw(pipeline)) {
            renderer.set_uniform(pipeline, descriptor_set, 0 * uniform_buffer.element_size());
            renderer.draw(mesh_buffer);
            renderer.end_draw();
         }

         renderer.wait_idle();
      }
   } catch (const std::exception &e) {
      std::cerr << "Unhandled exception: " << e.what() << "\n";
   }

   return 0;
}
