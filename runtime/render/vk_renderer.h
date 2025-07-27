#pragma once

#include <cstdint>
#include <initializer_list>
#include <span>
#include <unordered_map>
#include <unordered_set>
#include <variant>
#include <vector>

#include <vulkan/vulkan_core.h>

#include "ffi.h"
#include "gpu/vulkan/buffer.h"
#include "gpu/vulkan/command_pool.h"
#include "gpu/vulkan/descriptor_pool.h"
#include "gpu/vulkan/device.h"
#include "gpu/vulkan/gpu.h"
#include "gpu/vulkan/image.h"
#include "gpu/vulkan/physical_device.h"
#include "gpu/vulkan/pipeline.h"
#include "gpu/vulkan/shader.h"
#include "gpu/vulkan/swapchain.h"
#include "math/matrix.h"
#include "util/slab.h"

namespace simulo {

enum RenderPipeline : int {};
enum RenderImage : int {};

struct Pipelines {
   RenderPipeline ui;
   RenderPipeline mesh;
};

class MaterialProperties {
public:
   using MaterialPropertyValue = std::variant<Vec3, RenderImage>;

   MaterialProperties(
       const std::initializer_list<std::pair<const std::string, MaterialPropertyValue>> &&kv_pairs
   )
       : properties_(std::move(kv_pairs)) {}

   template <class T> T get(const std::string &key) const {
      if (!properties_.contains(key)) {
         return T();
      }

      const MaterialPropertyValue &value = properties_.at(key);
      if (!std::holds_alternative<T>(value)) {
         return T();
      }

      return std::get<T>(value);
   }

   bool has(const std::string &key) const {
      return properties_.contains(key);
   }

private:
   std::unordered_map<std::string, MaterialPropertyValue> properties_;
};

class Renderer {
public:
   explicit Renderer(
       Gpu &vk_instance, VkSurfaceKHR surface, uint32_t initial_width, uint32_t initial_height
   );
   ~Renderer();

   Mesh create_mesh(std::span<uint8_t> vertex_data, std::span<IndexBufferType> index_data);

   void delete_mesh(Mesh &mesh);

   RenderImage create_image(std::span<uint8_t> img_data, int width, int height);

   void
   update_mesh(Mesh &mesh, std::span<uint8_t> vertex_data, std::span<IndexBufferType> index_data);

   inline Device &device() {
      return device_;
   }

   inline PhysicalDevice &physical_device() {
      return physical_device_;
   }

   inline VkSampler image_sampler() const {
      return sampler_;
   }

   void begin_preframe();

   void buffer_copy(const StagingBuffer &src, VkBuffer dst);

   void upload_texture(const StagingBuffer &src, Image &image);

   inline void transfer_image_layout(Image &image, VkImageLayout layout) const {
      image.queue_transfer_layout(layout, preframe_cmd_buf_);
   }

   void end_preframe();

   bool render(Mat4 ui_view_projection, Mat4 world_view_projection);

   inline void wait_idle() const {
      device_.wait_idle();
   }

   void draw_pipeline(RenderPipeline pipeline_id, Mat4 view_projection);

   RenderPipeline create_pipeline(
       uint32_t vertex_size, VkDeviceSize uniform_size,
       const std::vector<VkVertexInputAttributeDescription> &attrs,
       std::span<const uint8_t> vertex_shader, std::span<const uint8_t> fragment_shader,
       const std::vector<VkDescriptorSetLayoutBinding> &bindings
   );

   void create_framebuffers();

   struct MaterialPipeline {
      VkDescriptorSetLayout descriptor_set_layout;
      Pipeline pipeline;
      VkDescriptorPool descriptor_pool;
      int uniform_slot_usage;
      UniformBuffer uniforms;
      Shader vertex_shader;
      Shader fragment_shader;
   };

   Gpu &vk_instance_;
   PhysicalDevice physical_device_;
   Device device_;
   Swapchain swapchain_;
   VkRenderPass render_pass_;
   std::vector<MaterialPipeline> pipelines_;
   Slab<Image> images_;
   std::vector<VkFramebuffer> framebuffers_;
   uint32_t current_framebuffer_;
   VkSampler sampler_;
   CommandPool command_pool_;
   VkCommandBuffer preframe_cmd_buf_;
   VkCommandBuffer command_buffer_;
   VkSemaphore sem_img_avail;
   VkSemaphore sem_render_complete;
   VkFence draw_cycle_complete;

   MaterialPipeline *last_bound_pipeline_;
   IndexBufferType last_bound_mesh_index_count_;

   StagingBuffer staging_buffer_;

   Pipelines pipeline_ids_;
};

}; // namespace simulo
