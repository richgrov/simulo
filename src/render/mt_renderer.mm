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

Renderer::Renderer(Gpu &gpu, void *pipeline_pixel_format, void *metal_layer)
    : gpu_(gpu), metal_layer_(reinterpret_cast<CAMetalLayer *>(metal_layer)), command_queue_(gpu) {
   simd::float3 triangle[] = {
       {0.0f, 0.5f, 0.0f},
       {0.5f, -0.5f, 0.0f},
       {-0.5f, -0.5f, 0.0f},
   };

   buffer_ = [gpu.device() newBufferWithBytes:triangle
                                       length:sizeof(triangle)
                                      options:MTLResourceStorageModeShared];
   if (buffer_ == nullptr) {
      throw std::runtime_error("error creating buffer");
   }

   id<MTLFunction> vertex_func = [gpu.library() newFunctionWithName:@"vertex"];
   id<MTLFunction> fragment_func = [gpu.library() newFunctionWithName:@"fragment"];

   MTLRenderPipelineDescriptor *pipeline_desc = [[MTLRenderPipelineDescriptor alloc] init];
   pipeline_desc.label = @"triangle";
   pipeline_desc.vertexFunction = vertex_func;
   pipeline_desc.fragmentFunction = fragment_func;
   pipeline_desc.colorAttachments[0].pixelFormat =
       static_cast<MTLPixelFormat>((NSUInteger)pipeline_pixel_format);

   NSError *err = nullptr;
   render_pipeline_state_ = [gpu.device() newRenderPipelineStateWithDescriptor:pipeline_desc
                                                                         error:&err];

   if (err != nullptr) {
      const char *message = [err.localizedDescription UTF8String];
      throw std::runtime_error(std::format("error creating render pipeline state: {}", message));
   }

   [pipeline_desc release];
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
      color_attachments.clearColor = MTLClearColorMake(0.0f, 0.0f, 0.0f, 1.0f);
      color_attachments.storeAction = MTLStoreActionStore;

      id<MTLRenderCommandEncoder> render_encoder =
          [cmd_buf renderCommandEncoderWithDescriptor:render_pass_desc];
      [render_encoder setRenderPipelineState:render_pipeline_state_];
      [render_encoder setVertexBuffer:buffer_ offset:0 atIndex:0];
      [render_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
      [render_encoder endEncoding];

      [cmd_buf presentDrawable:drawable];
      [cmd_buf commit];
      [cmd_buf waitUntilCompleted];

      [render_pass_desc release];
   }
   return true;
}
