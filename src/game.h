#ifndef VILLA_GPU_VK_GPU_H_
#define VILLA_GPU_VK_GPU_H_

#include <chrono>
#include <vector>

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
#include "window/window.h" // IWYU pragma: export

namespace villa {

class Game {
   using Clock = std::chrono::high_resolution_clock;

public:
   explicit Game(const char *title);
   ~Game();

   template <class T> Pipeline create_pipeline() {
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
          device_.handle(), binding, attrs, {vertex_shader_, fragment_shader_}, render_pass_
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

   DescriptorPool create_descriptor_pool(const Pipeline &pipeline) {
      return DescriptorPool(device_.handle(), pipeline);
   }

   Image create_image(uint32_t width, uint32_t height) const {
      return Image(
          physical_device_, device_.handle(), VK_IMAGE_USAGE_TRANSFER_DST_BIT, width, height
      );
   }

   void begin_preframe();

   void buffer_copy(const StagingBuffer &src, Buffer &dst);

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

   inline bool left_clicking() const {
      return window_.left_clicking();
   }

   inline bool left_clicked_now() const {
      return !was_left_clicking_ && left_clicking();
   }

   inline float delta() const {
      return delta_.count();
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
   void handle_resize(VkSurfaceKHR surface, uint32_t width, uint32_t height);

   Window window_;
   Instance vk_instance_;
   VkSurfaceKHR surface_;
   PhysicalDevice physical_device_;
   Device device_;
   Swapchain swapchain_;
   VkRenderPass render_pass_;
   Shader vertex_shader_;
   Shader fragment_shader_;
   std::vector<VkFramebuffer> framebuffers_;
   uint32_t current_framebuffer_;
   CommandPool command_pool_;
   VkCommandBuffer command_buffer_;
   VkSemaphore sem_img_avail;
   VkSemaphore sem_render_complete;
   VkFence draw_cycle_complete;

   Clock::time_point last_frame_time_;
   std::chrono::duration<float> delta_;
   bool was_left_clicking_;
   int last_width_;
   int last_height_;
};

}; // namespace villa

#endif // !VILLA_GPU_VK_GPU_H_
