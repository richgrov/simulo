#include "mt_renderer.h"
#include "model.h"

#include <Foundation/Foundation.h>
#include <format>
#include <ranges>
#include <stdexcept>

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/NSObjCRuntime.h>

#include "ffi.h"
#include "gpu/gpu.h"
#include "gpu/metal/buffer.h"
#include "gpu/metal/command_queue.h"
#include "gpu/metal/image.h"
#include "math/vector.h"
#include "render/model.h"
#include "render/ui.h"
#include "ui.h"

using namespace simulo;

namespace {

constexpr UiVertex triangle[] = {
    {{0, 0, 0.0f}, {0.0f, 1.0f}},
    {{0, 1, 0.0f}, {0.0f, 0.0f}},
    {{1, 0, 0.0f}, {1.0f, 1.0f}},
    {{1, 1, 0.0f}, {1.0f, 0.0f}},
};

constexpr uint16_t indices[] = {0, 1, 2, 1, 3, 2};

} // namespace

Renderer::Renderer(Gpu &gpu, void *pipeline_pixel_format, void *metal_layer)
    : gpu_(gpu),
      images_(4),
      materials_(8),
      meshes_(32),
      instances_(64),
      metal_layer_(reinterpret_cast<CAMetalLayer *>(metal_layer)),
      geometry_(
          VertexIndexBuffer::concat(
              gpu_,
              std::span<const uint8_t>(
                  reinterpret_cast<const uint8_t *>(triangle), sizeof(triangle)
              ),
              std::span<const uint16_t>(indices, 6)
          )
      ),
      command_queue_(gpu) {
   pipelines_.ui = static_cast<RenderPipeline>(render_pipelines_.size());
   render_pipelines_.emplace_back(
       MaterialPipeline{
           .pipeline = Pipeline(gpu, pipeline_pixel_format, "ui", "vertex_main", "fragment_main"),
       }
   );

   pipelines_.mesh = static_cast<RenderPipeline>(render_pipelines_.size());
   render_pipelines_.emplace_back(
       MaterialPipeline{
           .pipeline =
               Pipeline(gpu, pipeline_pixel_format, "mesh", "vertex_main2", "fragment_main2"),
       }
   );

   MTLDepthStencilDescriptor *depth_desc = [MTLDepthStencilDescriptor new];
   depth_desc.depthCompareFunction = MTLCompareFunctionLessEqual;
   depth_desc.depthWriteEnabled = YES;
   depth_stencil_state_ = [gpu_.device() newDepthStencilStateWithDescriptor:depth_desc];
   if (depth_stencil_state_ == nil) {
      throw std::runtime_error("failed to create depth stencil state");
   }
}

Renderer::~Renderer() {}

RenderObject Renderer::add_object(RenderMesh mesh, Mat4 transform, RenderMaterial material) {
   int id = instances_.emplace(
       MeshInstance{
           .transform = transform,
           .mesh = mesh,
           .material = material,
       }
   );

   Material &mat = materials_.get(material);
   if (mat.mesh_instances.contains(mesh)) {
      mat.mesh_instances[mesh].insert(id);
   } else {
      mat.mesh_instances.insert({mesh, {id}});
   }

   return static_cast<RenderObject>(id);
}

void Renderer::delete_object(RenderObject object) {
   MeshInstance &instance = instances_.get(object);

   Material &mat = materials_.get(instance.material);
   mat.mesh_instances[instance.mesh].erase(object);
   if (mat.mesh_instances[instance.mesh].empty()) {
      mat.mesh_instances.erase(instance.mesh);
   }

   instances_.release(object);
}

bool Renderer::render(Mat4 ui_view_projection, Mat4 world_view_projection) {
   @autoreleasepool {
      id<CAMetalDrawable> drawable = [metal_layer_ nextDrawable];

      id<MTLCommandBuffer> cmd_buf = command_queue_.command_buffer();
      MTLRenderPassDescriptor *render_pass_desc = [[MTLRenderPassDescriptor alloc] init];
      MTLRenderPassColorAttachmentDescriptor *color_attachments =
          render_pass_desc.colorAttachments[0];
      color_attachments.texture = drawable.texture;
      color_attachments.loadAction = MTLLoadActionClear;
      color_attachments.clearColor = MTLClearColorMake(0.f, 0.f, 0.f, 1.0f);
      color_attachments.storeAction = MTLStoreActionStore;

      id<MTLRenderCommandEncoder> render_encoder =
          [cmd_buf renderCommandEncoderWithDescriptor:render_pass_desc];

      [render_encoder setDepthStencilState:depth_stencil_state_];

      do_render_pipeline(pipelines_.mesh, (__bridge void *)render_encoder, world_view_projection);
      do_render_pipeline(pipelines_.ui, (__bridge void *)render_encoder, ui_view_projection);

      [render_encoder endEncoding];

      [cmd_buf presentDrawable:drawable];
      [cmd_buf commit];
      [cmd_buf waitUntilCompleted];

      [render_pass_desc release];
   }
   return true;
}

void Renderer::do_render_pipeline(RenderPipeline pipeline_id, void *render_enc, Mat4 projection) {
   auto render_encoder = (__bridge id<MTLRenderCommandEncoder>)render_enc;
   const MaterialPipeline &mat_pipeline = render_pipelines_[pipeline_id];
   [render_encoder setRenderPipelineState:mat_pipeline.pipeline.pipeline_state()];

   for (int mat_id : mat_pipeline.materials) {
      const Material &mat = materials_.get(mat_id);

      [render_encoder setFragmentBuffer:mat.uniform_buffer.buffer() offset:0 atIndex:0];

      for (int i = 0; i < mat.images.size(); ++i) {
         RenderImage img_id = mat.images[i];
         const Image &img = images_.get(img_id);
         [render_encoder setFragmentTexture:img.texture() atIndex:0];
      }

      for (const auto &[mesh_id, instances] : mat.mesh_instances) {
         VertexIndexBuffer &buf = meshes_.get(mesh_id);
         [render_encoder setVertexBuffer:buf.buffer() offset:0 atIndex:0];

         for (int instance_id : instances) {
            const MeshInstance &instance = instances_.get(instance_id);
            Mat4 transform = projection * instance.transform;
            [render_encoder setVertexBytes:reinterpret_cast<void *>(&transform)
                                    length:sizeof(Mat4)
                                   atIndex:1];

            [render_encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                       indexCount:buf.num_indices()
                                        indexType:VertexIndexBuffer::kIndexType
                                      indexBuffer:buf.buffer()
                                indexBufferOffset:buf.index_offset()];
         }
      }
   }
}
