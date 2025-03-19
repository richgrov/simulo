#include "mt_renderer.h"

#include <format>
#include <ranges>
#include <stdexcept>

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/NSObjCRuntime.h>
#import <simd/simd.h>

#include "gpu/gpu.h"
#include "gpu/metal/command_queue.h"

using namespace vkad;

namespace {

constexpr simd::float3 triangle[] = {
    {0.0f, 0.5f, 0.0f},
    {0.5f, -0.5f, 0.0f},
    {-0.5f, -0.5f, 0.0f},
};

}

Renderer::Renderer(Gpu &gpu, void *pipeline_pixel_format, void *metal_layer)
    : gpu_(gpu),
      metal_layer_(reinterpret_cast<CAMetalLayer *>(metal_layer)),
      ui_pipeline_(gpu, pipeline_pixel_format),
      vertex_buffer_(
          gpu_,
          std::span<const uint8_t>(reinterpret_cast<const uint8_t *>(triangle), sizeof(triangle))
      ),
      command_queue_(gpu) {}

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
      color_attachments.clearColor = MTLClearColorMake(0.0f, 0.0f, 0.0f, 1.0f);
      color_attachments.storeAction = MTLStoreActionStore;

      id<MTLRenderCommandEncoder> render_encoder =
          [cmd_buf renderCommandEncoderWithDescriptor:render_pass_desc];
      [render_encoder setRenderPipelineState:ui_pipeline_.pipeline_state()];
      [render_encoder setVertexBuffer:vertex_buffer_.buffer() offset:0 atIndex:0];
      [render_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
      [render_encoder endEncoding];

      [cmd_buf presentDrawable:drawable];
      [cmd_buf commit];
      [cmd_buf waitUntilCompleted];

      [render_pass_desc release];
   }
   return true;
}
