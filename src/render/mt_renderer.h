#pragma once

#include <span>
#include <unordered_set>
#include <utility>
#include <variant>

#ifdef __OBJC__
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#endif

#include "gpu/gpu.h"
#include "gpu/metal/buffer.h"
#include "gpu/metal/command_queue.h"
#include "gpu/metal/image.h"
#include "gpu/metal/render_pipeline.h"
#include "math/matrix.h"
#include "math/vector.h"
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
   using IndexBufferType = uint32_t;

   Renderer(Gpu &gpu, void *pipeline_pixel_format, void *metal_layer);
   ~Renderer();

   template <class Uniform>
   RenderMaterial create_material(RenderPipeline pipeline_id, const MaterialProperties &props) {
      int id = materials_.emplace(Material{
          .pipeline = pipeline_id,
      });

      MaterialPipeline &pipeline = render_pipelines_[pipeline_id];
      pipeline.materials.insert(id);

      return static_cast<RenderMaterial>(id);
   }

   RenderMesh create_mesh(std::span<uint8_t> vertex_data, std::span<IndexBufferType> index_data) {
      return static_cast<RenderMesh>(0);
   }

   void delete_mesh(RenderMesh mesh) const {}

   RenderObject add_object(RenderMesh mesh, Mat4 transform, RenderMaterial material) const {
      return static_cast<RenderObject>(0);
   }

   void delete_object(RenderObject object) {}

   RenderImage create_image(std::span<uint8_t> img_data, int width, int height) {
      int id = images_.emplace(gpu_, img_data, width, height);
      return static_cast<RenderImage>(id);
   }

   bool render(Mat4 ui_view_projection, Mat4 world_view_projection);

   void recreate_swapchain() const {}

   void wait_idle() {}

   const Pipelines &pipelines() {
      return pipelines_;
   }

private:
   void do_render_pipeline(RenderPipeline pipeline, void *render_enc);

   Gpu &gpu_;

#ifdef __OBJC__
   CAMetalLayer *metal_layer_;
#else
   void *metal_layer_;
#endif

   struct Material {
      RenderPipeline pipeline;
   };

   struct MaterialPipeline {
      Pipeline pipeline;
      std::unordered_set<int> materials;
   };

   std::vector<MaterialPipeline> render_pipelines_;
   Slab<Image> images_;
   Slab<Material> materials_;
   Buffer vertex_buffer_;
   Pipelines pipelines_;
   CommandQueue command_queue_;
};

} // namespace vkad
