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

bool begin_render(Renderer *renderer) {
   renderer->render_pool_ = [[NSAutoreleasePool alloc] init];

   renderer->drawable_ = [renderer->metal_layer_ nextDrawable];

   renderer->cmd_buf_ = renderer->command_queue_.command_buffer();
   renderer->render_pass_desc_ = [[MTLRenderPassDescriptor alloc] init];
   MTLRenderPassColorAttachmentDescriptor *color_attachments =
       renderer->render_pass_desc_.colorAttachments[0];
   color_attachments.texture = renderer->drawable_.texture;
   color_attachments.loadAction = MTLLoadActionClear;
   color_attachments.clearColor = MTLClearColorMake(0.f, 0.f, 0.f, 1.0f);
   color_attachments.storeAction = MTLStoreActionStore;

   renderer->render_encoder_ =
       [renderer->cmd_buf_ renderCommandEncoderWithDescriptor:renderer->render_pass_desc_];
   [renderer->render_encoder_ setDepthStencilState:renderer->depth_stencil_state_];
   return true;
}

void end_render(Renderer *renderer) {
   [renderer->render_encoder_ endEncoding];

   [renderer->cmd_buf_ presentDrawable:renderer->drawable_];
   [renderer->cmd_buf_ commit];
   [renderer->cmd_buf_ waitUntilCompleted];

   [renderer->render_pass_desc_ release];
   [renderer->render_pool_ drain];
}

void set_pipeline(Renderer *renderer, uint32_t pipeline_id_unused) {
   auto pipeline_id = renderer->pipelines_.ui; // TODO
   const MaterialPipeline &mat_pipeline = renderer->render_pipelines_[pipeline_id];
   [renderer->render_encoder_ setRenderPipelineState:mat_pipeline.pipeline.pipeline_state()];
}

void set_material(Renderer *renderer, uint32_t material_id) {
   const Material &mat = renderer->materials_.get(material_id);
   [renderer->render_encoder_ setFragmentBuffer:mat.uniform_buffer.buffer() offset:0 atIndex:0];

   for (int i = 0; i < mat.images.size(); ++i) {
      RenderImage img_id = mat.images[i];
      const Image &img = renderer->images_.get(img_id);
      [renderer->render_encoder_ setFragmentTexture:img.texture() atIndex:0];
   }
}

void render_mesh(
    Renderer *renderer, uint32_t material_id, uint32_t mesh_id, const float *projection
) {
   Mat4 mat4_projection;
   std::memcpy(&mat4_projection, projection, sizeof(Mat4));

   const Material &mat = renderer->materials_.get(material_id);
   const std::unordered_set<int> &instances =
       mat.mesh_instances.at(static_cast<RenderMesh>(mesh_id));

   VertexIndexBuffer &buf = renderer->meshes_.get(mesh_id);
   [renderer->render_encoder_ setVertexBuffer:buf.buffer() offset:0 atIndex:0];

   for (int instance_id : instances) {
      const MeshInstance &instance = renderer->instances_.get(instance_id);
      Mat4 transform = mat4_projection * instance.transform;
      [renderer->render_encoder_ setVertexBytes:reinterpret_cast<void *>(&transform)
                                         length:sizeof(Mat4)
                                        atIndex:1];

      [renderer->render_encoder_ drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                            indexCount:buf.num_indices()
                                             indexType:VertexIndexBuffer::kIndexType
                                           indexBuffer:buf.buffer()
                                     indexBufferOffset:buf.index_offset()];
   }
}
