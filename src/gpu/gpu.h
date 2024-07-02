#ifndef VILLA_GPU_VK_GPU_H_
#define VILLA_GPU_VK_GPU_H_

#include <vector>

#include <vulkan/vulkan_core.h>

#include "buffer.h"
#include "command_pool.h"
#include "pipeline.h"
#include "shader.h"
#include "swapchain.h"

namespace villa {

struct QueueFamilies;

class Gpu {
public:
   explicit Gpu();
   ~Gpu();

   void init(const std::vector<const char *> &extensions);

   inline VkInstance instance() const {
      return vk_instance_;
   }

   void connect_to_surface(VkSurfaceKHR surface, uint32_t width, uint32_t height);

   Pipeline create_pipeline() {
      VkVertexInputBindingDescription binding = {
          .binding = 0,
          .stride = (4 * 2) + (4 * 3),
          .inputRate = VK_VERTEX_INPUT_RATE_VERTEX,
      };

      std::vector<VkVertexInputAttributeDescription> attrs = {
          VkVertexInputAttributeDescription{
              .location = 0,
              .binding = 0,
              .format = VK_FORMAT_R32G32_SFLOAT,
              .offset = 0,
          },
          VkVertexInputAttributeDescription{
              .location = 1,
              .binding = 0,
              .format = VK_FORMAT_R32G32B32_SFLOAT,
              .offset = 4 * 2,
          },
      };

      return Pipeline(device_, binding, attrs, {vertex_shader_, fragment_shader_}, render_pass_);
   }

   template <class T> inline VertexBuffer allocate_vertex_buffer(size_t num_vertices) {
      return VertexBuffer(num_vertices, sizeof(T), device_, physical_device_);
   }

   void draw(const Pipeline &pipeline, const VertexBuffer &vertices);

private:
   bool init_physical_device(QueueFamilies *families, SwapchainCreationInfo *info);

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
   CommandPool command_pool_;
   VkCommandBuffer command_buffer_;
   VkSemaphore sem_img_avail;
   VkSemaphore sem_render_complete;
   VkFence draw_cycle_complete;
};

}; // namespace villa

#endif // !VILLA_GPU_VK_GPU_H_
