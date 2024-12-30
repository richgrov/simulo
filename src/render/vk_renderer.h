#ifndef VKAD_GPU_VK_GPU_H_
#define VKAD_GPU_VK_GPU_H_

#include <cstdint>
#include <initializer_list>
#include <span>
#include <unordered_map>
#include <unordered_set>
#include <variant>
#include <vector>

#include <vulkan/vulkan_core.h>

#include "gpu/vulkan/buffer.h"
#include "gpu/vulkan/command_pool.h"
#include "gpu/vulkan/descriptor_pool.h"
#include "gpu/vulkan/device.h"
#include "gpu/vulkan/image.h"
#include "gpu/vulkan/instance.h"
#include "gpu/vulkan/physical_device.h"
#include "gpu/vulkan/pipeline.h"
#include "gpu/vulkan/shader.h"
#include "gpu/vulkan/swapchain.h"
#include "math/mat4.h"
#include "mesh.h"
#include "util/slab.h"

namespace vkad {

enum RenderPipeline : int {};
enum RenderMaterial : int {};
enum RenderMesh : int {};
enum RenderObject : int {};
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
   using IndexBufferType = VertexIndexBuffer::IndexType;

   explicit Renderer(
       Instance &vk_instance, VkSurfaceKHR surface, uint32_t initial_width, uint32_t initial_height
   );
   ~Renderer();

   template <class Uniform>
   RenderMaterial create_material(RenderPipeline pipeline_id, const MaterialProperties &props) {
      MaterialPipeline &pipe = pipelines_[pipeline_id];
      int material_id = materials_.emplace(Material{
          .descriptor_set = pipe.descriptor_pool.allocate(pipe.descriptor_set_layout),
      });
      Material &mat = materials_.get(material_id);

      pipe.materials.insert(material_id);

      Uniform u(Uniform::from_props(props));
      pipe.uniforms.upload_memory(&u, sizeof(Uniform), 0);

      std::vector<DescriptorWrite> writes = {
          DescriptorPool::write_uniform_buffer_dynamic(pipe.uniforms),
      };

      if (props.has("image")) {
         RenderImage image_id = props.get<RenderImage>("image");
         writes.push_back(
             DescriptorPool::write_combined_image_sampler(image_sampler(), images_.get(image_id))
         );
      }

      pipe.descriptor_pool.write(mat.descriptor_set, writes);

      return static_cast<RenderMaterial>(material_id);
   }

   RenderMesh create_mesh(
       const std::span<uint8_t> vertex_data,
       const std::span<VertexIndexBuffer::IndexType> index_data
   );

   inline void delete_mesh(RenderMesh mesh) {
      meshes_.release(mesh);
   }

   RenderObject add_object(RenderMesh mesh, Mat4 transform, RenderMaterial material);

   void delete_object(RenderObject object);

   RenderImage create_image(std::span<uint8_t> img_data, int width, int height);

   void update_mesh(
       RenderMesh mesh, const std::span<uint8_t> vertex_data,
       const std::span<VertexIndexBuffer::IndexType> index_data
   ) {
      Mesh &renderer_mesh = meshes_.get(mesh);
      staging_buffer_.upload_mesh(vertex_data, index_data);
      begin_preframe();
      buffer_copy(staging_buffer_, renderer_mesh.vertices_indices);
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

   bool render(Mat4 ui_view_projection, Mat4 world_view_projection);

   inline void wait_idle() const {
      device_.wait_idle();
   }

   const Pipelines &pipelines() const {
      return pipeline_ids_;
   }

private:
   void draw_pipeline(RenderPipeline pipeline_id, Mat4 view_projection);

   RenderPipeline create_pipeline(
       uint32_t vertex_size, VkDeviceSize uniform_size,
       const std::vector<VkVertexInputAttributeDescription> &attrs,
       const std::span<uint8_t> vertex_shader, const std::span<uint8_t> fragment_shader,
       const std::vector<VkDescriptorSetLayoutBinding> &bindings
   );

   void create_framebuffers();

   struct MaterialPipeline {
      VkDescriptorSetLayout descriptor_set_layout;
      Pipeline pipeline;
      DescriptorPool descriptor_pool;
      UniformBuffer uniforms;
      Shader vertex_shader;
      Shader fragment_shader;
      std::unordered_set<int> materials;
   };

   struct Material {
      VkDescriptorSet descriptor_set;
      std::unordered_map<RenderMesh, std::unordered_set<RenderObject>> instances;
   };

   struct Mesh {
      VertexIndexBuffer vertices_indices;
   };

   struct MeshInstance {
      Mat4 transform;
      RenderMesh mesh_id;
      RenderMaterial material_id;
   };

   Instance &vk_instance_;
   PhysicalDevice physical_device_;
   Device device_;
   Swapchain swapchain_;
   VkRenderPass render_pass_;
   std::vector<MaterialPipeline> pipelines_;
   Slab<Material> materials_;
   Slab<MeshInstance> objects_;
   Slab<Mesh> meshes_;
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

   StagingBuffer staging_buffer_;

   Pipelines pipeline_ids_;
};

}; // namespace vkad

#endif // !VKAD_GPU_VK_GPU_H_
