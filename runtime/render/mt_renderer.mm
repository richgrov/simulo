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
#include "gpu/metal/command_queue.h"
#include "gpu/metal/image.h"
#include "math/vector.h"
#include "render/model.h"
#include "render/ui.h"
#include "ui.h"
#include "util/memory.h"

using namespace simulo;

namespace {} // namespace

Renderer::Renderer(Gpu &gpu, void *pipeline_pixel_format, void *metal_layer)
    : gpu_(gpu),
      images_(4),
      materials_(1024),
      metal_layer_(reinterpret_cast<CAMetalLayer *>(metal_layer)),
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

RenderMaterial Renderer::do_create_material(
    RenderPipeline pipeline_id, void *data, size_t size, std::vector<RenderImage> &&images
) {
   id<MTLBuffer> buf = [gpu_.device() newBufferWithBytes:data
                                                  length:size
                                                 options:MTLResourceStorageModeShared];
   int id = materials_.emplace(
       Material{
           .pipeline = pipeline_id,
           .uniform_buffer = buf,
           .images = std::move(images),
       }
   );

   return static_cast<RenderMaterial>(id);
}

Mesh create_mesh(
    Renderer *renderer, uint8_t *vertex_data, size_t vertex_data_size, IndexBufferType *index_data,
    size_t index_count
) {
   size_t indices_start = align_to(vertex_data_size, (size_t)4);
   size_t indices_size = index_count * sizeof(IndexBufferType);

   std::vector<uint8_t> data(indices_start + indices_size);
   memcpy(data.data(), vertex_data, vertex_data_size);
   memcpy(data.data() + indices_start, index_data, indices_size);

   return Mesh{
       .buffer = [renderer->gpu_.device() newBufferWithBytes:data.data()
                                                      length:data.size()
                                                     options:MTLResourceStorageModeShared],
       .indices_start = indices_start,
       .num_indices = static_cast<IndexBufferType>(index_count),
   };
}

void delete_mesh(Renderer *renderer, Mesh *mesh) {
   [mesh->buffer release];
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
   [renderer->render_encoder_ setFragmentBuffer:mat.uniform_buffer offset:0 atIndex:0];

   for (int i = 0; i < mat.images.size(); ++i) {
      RenderImage img_id = mat.images[i];
      const Image &img = renderer->images_.get(img_id);
      [renderer->render_encoder_ setFragmentTexture:img.texture() atIndex:0];
   }
}

void set_mesh(Renderer *renderer, Mesh *mesh) {
   renderer->last_binded_mesh_ = mesh;
   [renderer->render_encoder_ setVertexBuffer:mesh->buffer offset:0 atIndex:0];
}

void render_object(Renderer *renderer, const float *transform) {
   [renderer->render_encoder_ setVertexBytes:reinterpret_cast<const void *>(transform)
                                      length:sizeof(Mat4)
                                     atIndex:1];

   static_assert(sizeof(IndexBufferType) == 2, "IndexBufferType != MTLIndexTypeUInt16");

   [renderer->render_encoder_ drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                         indexCount:renderer->last_binded_mesh_->num_indices
                                          indexType:MTLIndexTypeUInt16
                                        indexBuffer:renderer->last_binded_mesh_->buffer
                                  indexBufferOffset:renderer->last_binded_mesh_->indices_start];
}
