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

struct Pipelines {
   uint16_t ui;
   uint16_t mesh;
};

class MaterialProperties {
public:
   using MaterialPropertyValue = std::variant<Vec3, int>;

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
       Instance &vk_instance, VkSurfaceKHR surface, uint32_t initial_width, uint32_t initial_height
   );
   ~Renderer();

   template <class Uniform> int create_material(int pipeline_id, const MaterialProperties &props) {
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
         int image_id = props.get<int>("image");
         writes.push_back(
             DescriptorPool::write_combined_image_sampler(image_sampler(), images_.get(image_id))
         );
      }

      pipe.descriptor_pool.write(mat.descriptor_set, writes);

      return material_id;
   }

   template <class Vertex> inline void init_mesh(Mesh<Vertex> &mesh) {
      mesh.id_ = meshes_.emplace(Mesh{
          .vertices_indices = VertexIndexBuffer(
              mesh.vertices_.size(), sizeof(Vertex), mesh.indices_.size(), device_.handle(),
              physical_device_
          ),
      });
      update_mesh(mesh);
   }

   template <class Vertex> inline void delete_mesh(Mesh<Vertex> &mesh) {
      meshes_.release(mesh.id_);
#ifdef VKAD_DEBUG
      mesh.id_ = -1;
#endif
   }

   template <class T> UniformBuffer create_uniform_buffer(size_t num_elements) {
      return UniformBuffer(sizeof(T), num_elements, device_.handle(), physical_device_);
   }

   int add_object(int mesh_id, Mat4 transform, int material_id) {
      int object_id = objects_.emplace(MeshInstance{
          .transform = transform,
          .mesh_id = mesh_id,
          .material_id = material_id,
      });
      meshes_.get(mesh_id).instances.insert(object_id);

      Material &mat = materials_.get(material_id);
      if (mat.instances.contains(mesh_id)) {
         mat.instances.at(mesh_id).insert(object_id);
      } else {
         std::unordered_set<int> instances = {object_id};
         mat.instances.emplace(mesh_id, std::move(instances));
      }

      return object_id;
   }

   void delete_object(int object_id) {
      MeshInstance &instance = objects_.get(object_id);
      materials_.get(instance.material_id).instances.at(instance.mesh_id).erase(object_id);
      meshes_.get(instance.mesh_id).instances.erase(object_id);
      objects_.release(object_id);
   }

   int create_image(std::span<uint8_t> img_data, int width, int height) {
      int image_id = images_.emplace(
          physical_device_, device_.handle(),
          VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT, VK_FORMAT_R8_UNORM, width,
          height
      );
      Image &image = images_.get(image_id);

      staging_buffer_.upload_raw(img_data.data(), img_data.size());
      begin_preframe();
      transfer_image_layout(image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
      upload_texture(staging_buffer_, image);
      transfer_image_layout(image, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
      end_preframe();

      image.init_view();
      return image_id;
   }

   template <class Vertex> void update_mesh(Mesh<Vertex> &mesh) {
      Mesh &renderer_mesh = meshes_.get(mesh.id_);
      staging_buffer_.upload_mesh(
          mesh.vertices_.data(), sizeof(Vertex) * mesh.vertices_.size(), mesh.indices_.data(),
          mesh.indices_.size()
      );
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

   bool begin_draw();

   void draw_pipeline(int pipeline_id, Mat4 view_projection);

   void draw(int mesh_id, Mat4 mvp);

   void end_draw();

   inline void wait_idle() const {
      device_.wait_idle();
   }

   const Pipelines &pipelines() const {
      return pipeline_ids_;
   }

private:
   uint16_t create_pipeline(
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
      std::unordered_map<int, std::unordered_set<int>> instances;
   };

   struct Mesh {
      VertexIndexBuffer vertices_indices;
      std::unordered_set<int> instances;
   };

   struct MeshInstance {
      Mat4 transform;
      int mesh_id;
      int material_id;
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
