#pragma once

#include <cstdint>
#include <span>
#include <unordered_set>
#include <utility>
#include <variant>

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#endif

#include "ffi.h"
#include "gpu/gpu.h"
#include "gpu/metal/command_queue.h"
#include "gpu/metal/image.h"
#include "gpu/metal/render_pipeline.h"
#include "math/matrix.h"
#include "math/vector.h"
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

struct MaterialPipeline {
   Pipeline pipeline;
};

class Renderer {
public:
   Renderer(Gpu &gpu, void *pipeline_pixel_format, void *metal_layer);
   ~Renderer();

   template <class Uniform>
   Material create_material(RenderPipeline pipeline_id, const MaterialProperties &props) {
      int image = -1;
      if (props.has("image")) {
         image = static_cast<int>(props.get<RenderImage>("image"));
      }

      Uniform data(Uniform::from_props(props));
      return do_create_material(pipeline_id, &data, sizeof(data), image);
   }

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

   Material do_create_material(RenderPipeline pipeline_id, void *data, size_t size, int image);

   Gpu &gpu_;

#ifdef __OBJC__
   CAMetalLayer *metal_layer_;
   _Nonnull id<MTLDepthStencilState> depth_stencil_state_;
   NSAutoreleasePool *render_pool_ = nullptr;
   MTLRenderPassDescriptor *render_pass_desc_ = nullptr;
   _Nullable id<CAMetalDrawable> drawable_ = nil;
   _Nullable id<MTLCommandBuffer> cmd_buf_ = nil;
   _Nullable id<MTLRenderCommandEncoder> render_encoder_ = nil;
#else
   void *metal_layer_;
   void *depth_stencil_state_;
   void *render_pool_;
   void *render_pass_desc_;
   void *drawable_;
   void *cmd_buf_;
   void *render_encoder_;
#endif

   std::vector<MaterialPipeline> render_pipelines_;
   Slab<Image> images_;
   Mesh *last_binded_mesh_;
   Pipelines pipelines_;
   CommandQueue command_queue_;
};

} // namespace simulo
