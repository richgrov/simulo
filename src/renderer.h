#ifndef VKAD_GPU_VK_GPU_H_
#define VKAD_GPU_VK_GPU_H_

#include <chrono>
#include <vector>

#include <fmod.h>
#include <vulkan/vulkan_core.h>

#include "entity/player.h"
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
#include "math/angle.h"
#include "math/mat4.h"
#include "sound.h"
#include "ui/font.h"
#include "window/window.h" // IWYU pragma: export

namespace vkad {

class Renderer {
   using Clock = std::chrono::high_resolution_clock;

public:
   explicit Renderer(const char *title);
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

   StagingBuffer create_staging_buffer(size_t capacity) {
      return StagingBuffer(capacity, device_.handle(), physical_device_);
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

   Sound create_sound(const char *path) {
      return Sound(sound_system_, path);
   }

   inline VkSampler image_sampler() const {
      return sampler_;
   }

   void begin_preframe();

   void buffer_copy(const StagingBuffer &src, Buffer &dst);

   void upload_texture(const StagingBuffer &src, Image &image);

   inline void transfer_image_layout(Image &image, VkImageLayout layout) const {
      image.queue_transfer_layout(layout, preframe_cmd_buf_);
   }

   void end_preframe();

   bool poll();

   inline int width() const {
      return window_.width();
   }

   inline int height() const {
      return window_.height();
   }

   inline int mouse_x() const {
      return window_.mouse_x();
   }

   inline int mouse_y() const {
      return window_.mouse_y();
   }

   inline int delta_mouse_x() const {
      return window_.delta_mouse_x();
   }

   inline int delta_mouse_y() const {
      return window_.delta_mouse_y();
   }

   inline bool left_clicking() const {
      return window_.left_clicking();
   }

   inline bool left_clicked_now() const {
      return !was_left_clicking_ && left_clicking();
   }

   inline bool is_key_down(uint8_t key_code) const {
      return window_.is_key_down(key_code);
   }

   inline float delta() const {
      return delta_.count();
   }

   inline Mat4 perspective_matrix() const {
      float aspect = static_cast<float>(window_.width()) / static_cast<float>(window_.height());
      return Mat4::perspective(aspect, deg_to_rad(70), 0.01, 100);
   }

   inline Player &player() {
      return player_;
   }

   bool begin_draw(const Pipeline &pipeline);

   void set_uniform(const Pipeline &pipeline, VkDescriptorSet descriptor_set, uint32_t offset);

   void draw(const VertexIndexBuffer &buffer);

   void end_draw();

   inline void wait_idle() const {
      device_.wait_idle();
   }

private:
   void create_framebuffers();
   void handle_resize(uint32_t width, uint32_t height);

   Instance vk_instance_;
   Window window_;
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

   Font font_;
   FMOD_SYSTEM *sound_system_;

   Clock::time_point last_frame_time_;
   std::chrono::duration<float> delta_;
   bool was_left_clicking_;
   int last_width_;
   int last_height_;

   Player player_;
};

}; // namespace vkad

#endif // !VKAD_GPU_VK_GPU_H_
