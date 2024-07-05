#ifndef VILLA_GPU_VK_GPU_H_
#define VILLA_GPU_VK_GPU_H_

#include <vector>

#include <vulkan/vulkan_core.h>

#include "gpu/buffer.h"
#include "gpu/command_pool.h"
#include "gpu/descriptor_pool.h"
#include "gpu/pipeline.h"
#include "gpu/shader.h"
#include "gpu/swapchain.h"
#include "window/window.h" // IWYU pragma: export

namespace villa {

struct QueueFamilies;

class Game {
public:
   explicit Game(const char *title);
   ~Game();

   void connect_to_surface(VkSurfaceKHR surface, uint32_t width, uint32_t height);

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

      return Pipeline(device_, binding, attrs, {vertex_shader_, fragment_shader_}, render_pass_);
   }

   template <class T>
   inline VertexIndexBuffer
   create_vertex_index_buffer(size_t num_vertices, VertexIndexBuffer::IndexType num_indices) {
      return VertexIndexBuffer(num_vertices, sizeof(T), num_indices, device_, physical_device_);
   }

   StagingBuffer create_staging_buffer(size_t capacity) {
      return StagingBuffer(capacity, device_, physical_device_);
   }

   template <class T> UniformBuffer create_uniform_buffer(size_t num_elements) {
      return UniformBuffer(sizeof(T) * num_elements, device_, physical_device_);
   }

   DescriptorPool create_descriptor_pool(const Pipeline &pipeline) {
      return DescriptorPool(device_, pipeline);
   }

   void buffer_copy(const StagingBuffer &src, Buffer &dst);

   inline bool poll() {
      return window_.poll();
   }

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

   void begin_draw(const Pipeline &pipeline, VkDescriptorSet descriptor_set);

   void draw(const VertexIndexBuffer &buffer);

   void end_draw();

   inline void wait_idle() const {
      vkDeviceWaitIdle(device_);
   }

private:
   bool init_physical_device(QueueFamilies *families, SwapchainCreationInfo *info);

   Window window_;
   VkInstance vk_instance_;
   VkPhysicalDevice physical_device_;
   VkDevice device_;
   VkSurfaceKHR surface_;
   VkQueue graphics_queue_;
   VkQueue present_queue_;
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
};

}; // namespace villa

#endif // !VILLA_GPU_VK_GPU_H_
