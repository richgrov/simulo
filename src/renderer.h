#ifndef VKAD_GPU_VK_GPU_H_
#define VKAD_GPU_VK_GPU_H_

#include <cstdint>
#include <string>
#include <unordered_map>
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
#include "gpu/swapchain.h"
#include "mesh.h"

namespace vkad {

class Renderer {
public:
   explicit Renderer(
       Instance &vk_instance, VkSurfaceKHR surface, uint32_t initial_width, uint32_t initial_height
   );
   ~Renderer();

   template <class Vertex>
   int create_material(
       const std::vector<std::string> &shader_paths,
       const std::vector<VkDescriptorSetLayoutBinding> &bindings
   ) {
      std::vector<VkVertexInputAttributeDescription> attrs(
          Vertex::attributes.begin(), Vertex::attributes.end()
      );

      return do_create_pipeline(sizeof(Vertex), attrs, shader_paths, bindings);
   }

   int do_create_pipeline(
       uint32_t vertex_size, const std::vector<VkVertexInputAttributeDescription> &attrs,
       const std::vector<std::string> &shader_paths,
       const std::vector<VkDescriptorSetLayoutBinding> &bindings
   );

   void link_material(int material_id, const std::vector<DescriptorWrite> &writes) {
      Material &mat = materials_[material_id];
      mat.descriptor_set = mat.descriptor_pool.allocate(mat.descriptor_set_layout);
      mat.descriptor_pool.write(mat.descriptor_set, writes);
   }

   void ensure_shader_loaded(const std::string &path);

   template <class Vertex> inline void init_mesh(Mesh<Vertex> &mesh) {
      meshes_.emplace_back(
          mesh.vertices_.size(), sizeof(Vertex), mesh.indices_.size(), device_.handle(),
          physical_device_
      );
      mesh.id_ = meshes_.size() - 1;
   }

   template <class T> UniformBuffer create_uniform_buffer(size_t num_elements) {
      return UniformBuffer(sizeof(T), num_elements, device_.handle(), physical_device_);
   }

   Image create_image(uint32_t width, uint32_t height) const {
      return Image(
          physical_device_, device_.handle(),
          VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT, VK_FORMAT_R8G8B8A8_SRGB,
          width, height
      );
   }

   void init_image(Image &image, unsigned char *img_data, size_t size) {
      staging_buffer_.upload_raw(img_data, size);
      begin_preframe();
      transfer_image_layout(image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
      upload_texture(staging_buffer_, image);
      transfer_image_layout(image, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
      end_preframe();
      image.init_view();
   }

   template <class Vertex> void update_mesh(Mesh<Vertex> &mesh) {
      VertexIndexBuffer &buf = meshes_[mesh.id_];
      staging_buffer_.upload_mesh(
          mesh.vertices_.data(), sizeof(Vertex) * mesh.vertices_.size(), mesh.indices_.data(),
          mesh.indices_.size()
      );
      begin_preframe();
      buffer_copy(staging_buffer_, buf);
      end_preframe();
   }

   inline Device &device() {
      return device_;
   }

   inline PhysicalDevice &physical_device() {
      return physical_device_;
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

   bool begin_draw();

   void set_material(int material_id);

   void set_uniform(int material_id, uint32_t offset);

   void draw(int mesh_id);

   void end_draw();

   inline void wait_idle() const {
      device_.wait_idle();
   }

private:
   void create_framebuffers();

   struct Material {
      VkDescriptorSetLayout descriptor_set_layout;
      Pipeline pipeline;
      DescriptorPool descriptor_pool;
      VkDescriptorSet descriptor_set;
   };

   Instance &vk_instance_;
   PhysicalDevice physical_device_;
   Device device_;
   Swapchain swapchain_;
   VkRenderPass render_pass_;
   std::vector<Material> materials_;
   std::unordered_map<std::string, Shader> shaders_;
   std::vector<VertexIndexBuffer> meshes_;
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
