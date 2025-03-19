#include "mt_renderer.h"
#include "gpu/metal/image.h"
#include "render/ui.h"

#include <Foundation/Foundation.h>
#include <format>
#include <ranges>
#include <stdexcept>

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/NSObjCRuntime.h>

#include "gpu/gpu.h"
#include "gpu/metal/command_queue.h"
#include "math/vector.h"

using namespace vkad;

namespace {

constexpr UiVertex triangle[] = {
    {{-0.5f, -0.5f, 0.0f}, {0.0f, 1.0f}}, {{-0.5f, 0.5f, 0.0f}, {0.0f, 0.0f}},
    {{0.5f, -0.5f, 0.0f}, {1.0f, 1.0f}},  {{-0.5f, 0.5f, 0.0f}, {0.0f, 0.0f}},
    {{0.5f, 0.5f, 0.0f}, {1.0f, 0.0f}},   {{0.5f, -0.5f, 0.0f}, {1.0f, 1.0f}},
};

}

Renderer::Renderer(Gpu &gpu, void *pipeline_pixel_format, void *metal_layer)
    : gpu_(gpu),
      images_(4),
      materials_(8),
      metal_layer_(reinterpret_cast<CAMetalLayer *>(metal_layer)),
      vertex_buffer_(
          gpu_,
          std::span<const uint8_t>(reinterpret_cast<const uint8_t *>(triangle), sizeof(triangle))
      ),
      command_queue_(gpu) {

   pipelines_.ui = static_cast<RenderPipeline>(render_pipelines_.size());
   render_pipelines_.emplace_back(MaterialPipeline{
       .pipeline = Pipeline(gpu, pipeline_pixel_format, "ui", "vertex_main", "fragment_main"),
   });

   pipelines_.mesh = static_cast<RenderPipeline>(render_pipelines_.size());
   render_pipelines_.emplace_back(MaterialPipeline{
       .pipeline = Pipeline(gpu, pipeline_pixel_format, "mesh", "vertex_main2", "fragment_main2"),
   });
}

Renderer::~Renderer() {}

bool Renderer::render(Mat4 ui_view_projection, Mat4 world_view_projection) {
   @autoreleasepool {
      id<CAMetalDrawable> drawable = [metal_layer_ nextDrawable];

      id<MTLCommandBuffer> cmd_buf = command_queue_.command_buffer();
      MTLRenderPassDescriptor *render_pass_desc = [[MTLRenderPassDescriptor alloc] init];
      MTLRenderPassColorAttachmentDescriptor *color_attachments =
          render_pass_desc.colorAttachments[0];
      color_attachments.texture = drawable.texture;
      color_attachments.loadAction = MTLLoadActionClear;
      color_attachments.clearColor = MTLClearColorMake(0.4f, 0.4f, 0.4f, 1.0f);
      color_attachments.storeAction = MTLStoreActionStore;

      id<MTLRenderCommandEncoder> render_encoder =
          [cmd_buf renderCommandEncoderWithDescriptor:render_pass_desc];

      do_render_pipeline(pipelines_.ui, (__bridge void *)render_encoder);

      [cmd_buf presentDrawable:drawable];
      [cmd_buf commit];
      [cmd_buf waitUntilCompleted];

      [render_pass_desc release];
   }
   return true;
}

void Renderer::do_render_pipeline(RenderPipeline pipeline_id, void *render_enc) {
   auto render_encoder = (__bridge id<MTLRenderCommandEncoder>)render_enc;
   const MaterialPipeline &mat_pipeline = render_pipelines_[pipeline_id];
   [render_encoder setRenderPipelineState:mat_pipeline.pipeline.pipeline_state()];

   for (int mat_id : mat_pipeline.materials) {
      const Material &mat = materials_.get(mat_id);

      for (int i = 0; i < mat.images.size(); ++i) {
         RenderImage img_id = mat.images[i];
         const Image &img = images_.get(img_id);
         [render_encoder setFragmentTexture:img.texture() atIndex:0];
      }

      [render_encoder setVertexBuffer:vertex_buffer_.buffer() offset:0 atIndex:0];
      [render_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
   }

   [render_encoder endEncoding];
}
