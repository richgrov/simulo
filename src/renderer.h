#ifndef VKAD_GPU_VK_GPU_H_
#define VKAD_GPU_VK_GPU_H_

#include <vector>

#include <fmod.h>
#include <vulkan/vulkan_core.h>

#include "gpu/buffer.h"
#include "gpu/command_pool.h"
#include "gpu/descriptor_pool.h"
#include "gpu/device.h"
#include "gpu/image.h"
#include "gpu/instance.h"
#include "gpu/physical_device.h"
#include "gpu/pipeline.h"
#include "gpu/shader.h"
#include "gpu/swapchain.h"
#include "ui/font.h"
#include "ui/ui.h"

namespace vkad {

class Renderer {
public:
   explicit Renderer(
       Instance &vk_instance, VkSurfaceKHR surface, uint32_t initial_width, uint32_t initial_height
   );
   ~Renderer();

   template <class T> Pipeline create_pipeline(const DescriptorPool &descriptor_pool) {
      VkVertexInputBindingDescription binding = {
          .binding = 0,
          .stride = sizeof(T),
          .inputRate = VK_VERTEX_INPUT_RATE_VERTEX,
      };

      std::vector<VkVertexInputAttributeDescription> attrs(T::attributes.size());
      uint32_t offset = 0;
      for (uint32_t i = 0; i < T::attributes.size(); ++i) {
         const auto &attr = T::attributes[i];
         attrs[i] = {
             .location = i,
             .binding = 0,
             .format = attr.format,
             .offset = offset,
         };
         offset += attr.size;
      }

      return Pipeline(
          device_.handle(), binding, attrs, {vertex_shader_, fragment_shader_},
          descriptor_pool.layout(), render_pass_
      );
   }

   template <class T>
   inline VertexIndexBuffer
   create_vertex_index_buffer(size_t num_vertices, VertexIndexBuffer::IndexType num_indices) {
      return VertexIndexBuffer(
          num_vertices, sizeof(T), num_indices, device_.handle(), physical_device_
      );
   }

   template <class T> UniformBuffer create_uniform_buffer(size_t num_elements) {
      return UniformBuffer(sizeof(T), num_elements, device_.handle(), physical_device_);
   }

   DescriptorPool create_descriptor_pool() {
      return DescriptorPool(
          device_.handle(),
          {
              {
                  .binding = 0,
                  .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
                  .descriptorCount = 1,
                  .stageFlags = VK_SHADER_STAGE_VERTEX_BIT,
              },

              {
                  .binding = 1,
                  .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                  .descriptorCount = 1,
                  .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT,
              },
          },
          1
      );
   }

   Image create_image(uint32_t width, uint32_t height) const {
      return Image(
          physical_device_, device_.handle(),
          VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT, VK_FORMAT_R8G8B8A8_SRGB,
          width, height
      );
   }

   Font create_font(const std::string &path) {
      Font font(path, physical_device_, device_.handle());
      Image &image = font.image();

      staging_buffer_.upload_raw(font.image_data(), 512 * 512);
      begin_preframe();
      transfer_image_layout(image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
      upload_texture(staging_buffer_, image);
      transfer_image_layout(image, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
      end_preframe();

      image.init_view();
      return font;
   }

   VertexIndexBuffer create_text(Font &font, const std::string &text);

   void upload_mesh(
       void *vertex_data, size_t vertices_size, VertexIndexBuffer::IndexType *indices,
       VertexIndexBuffer::IndexType num_indices, VertexIndexBuffer &buf
   ) {
      staging_buffer_.upload_mesh(vertex_data, vertices_size, indices, num_indices);
      begin_preframe();
      buffer_copy(staging_buffer_, buf);
      end_preframe();
   }

   inline VkSampler image_sampler() const {
      return sampler_;
   }

   void recreate_swapchain(uint32_t width, uint32_t height, VkSurfaceKHR surface);

   void begin_preframe();

   void buffer_copy(const StagingBuffer &src, Buffer &dst);

   void upload_texture(const StagingBuffer &src, Image &image);

   inline void transfer_image_layout(Image &image, VkImageLayout layout) const {
      image.queue_transfer_layout(layout, preframe_cmd_buf_);
   }

   void end_preframe();

   bool begin_draw(const Pipeline &pipeline);

   void set_uniform(const Pipeline &pipeline, VkDescriptorSet descriptor_set, uint32_t offset);

   void draw(const VertexIndexBuffer &buffer);

   void end_draw();

   inline void wait_idle() const {
      device_.wait_idle();
   }

private:
   void create_framebuffers();

   Instance &vk_instance_;
   PhysicalDevice physical_device_;
   Device device_;
   Swapchain swapchain_;
   VkRenderPass render_pass_;
   Shader vertex_shader_;
   Shader fragment_shader_;
   std::vector<VkFramebuffer> framebuffers_;
   uint32_t current_framebuffer_;
   VkSampler sampler_;
   CommandPool command_pool_;
   VkCommandBuffer preframe_cmd_buf_;
   VkCommandBuffer command_buffer_;
   VkSemaphore sem_img_avail;
   VkSemaphore sem_render_complete;
   VkFence draw_cycle_complete;

   StagingBuffer staging_buffer_;
};

}; // namespace vkad

#endif // !VKAD_GPU_VK_GPU_H_
