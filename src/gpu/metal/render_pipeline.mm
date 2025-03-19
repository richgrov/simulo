#include "render_pipeline.h"

#include <format>
#include <stdexcept>

#include "gpu/gpu.h"

using namespace vkad;

Pipeline::Pipeline(const Gpu &gpu, void *pixel_format) {
   id<MTLFunction> vertex_func = [gpu.library() newFunctionWithName:@"vertex_main"];
   if (vertex_func == nullptr) {
      throw std::runtime_error("vertex function not found");
   }

   id<MTLFunction> fragment_func = [gpu.library() newFunctionWithName:@"fragment_main"];
   if (fragment_func == nullptr) {
      throw std::runtime_error("fragment function not found");
   }

   MTLRenderPipelineDescriptor *pipeline_desc = [[MTLRenderPipelineDescriptor alloc] init];
   pipeline_desc.label = @"triangle";
   pipeline_desc.vertexFunction = vertex_func;
   pipeline_desc.fragmentFunction = fragment_func;
   pipeline_desc.colorAttachments[0].pixelFormat =
       static_cast<MTLPixelFormat>((NSUInteger)pixel_format);

   NSError *err = nullptr;
   pipeline_state_ = [gpu.device() newRenderPipelineStateWithDescriptor:pipeline_desc error:&err];

   if (err != nullptr) {
      const char *message = [err.localizedDescription UTF8String];
      throw std::runtime_error(std::format("error creating render pipeline state: {}", message));
   }

   [pipeline_desc release];
}

Pipeline::~Pipeline() {
   [pipeline_state_ release];
}
