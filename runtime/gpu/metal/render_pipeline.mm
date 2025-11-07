#include "render_pipeline.h"

#include <Metal/Metal.h>

#include <format>
#include <stdexcept>

#include "gpu/gpu.h"

using namespace simulo;

// Pipeline::Pipeline(
//     const Gpu &gpu, void *pixel_format, const char *label, const char *vertex_fn,
//     const char *fragment_fn
// ) {
//    @autoreleasepool {
//       id<MTLFunction> vertex_func =
//           [gpu.library() newFunctionWithName:[NSString stringWithUTF8String:vertex_fn]];
//       if (vertex_func == nullptr) {
//          throw std::runtime_error("vertex function not found");
//       }

//       id<MTLFunction> fragment_func =
//           [gpu.library() newFunctionWithName:[NSString stringWithUTF8String:fragment_fn]];
//       if (fragment_func == nullptr) {
//          throw std::runtime_error("fragment function not found");
//       }

//       MTLRenderPipelineDescriptor *pipeline_desc = [[MTLRenderPipelineDescriptor alloc] init];
//       pipeline_desc.label = [NSString stringWithUTF8String:label];
//       pipeline_desc.vertexFunction = vertex_func;
//       pipeline_desc.fragmentFunction = fragment_func;
//       pipeline_desc.colorAttachments[0].blendingEnabled = true;
//       pipeline_desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
//       pipeline_desc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
//       pipeline_desc.colorAttachments[0].destinationRGBBlendFactor =
//           MTLBlendFactorOneMinusSourceAlpha;
//       pipeline_desc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
//       pipeline_desc.colorAttachments[0].pixelFormat =
//           static_cast<MTLPixelFormat>((NSUInteger)pixel_format);
//       pipeline_desc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

//       NSError *err = nullptr;
//       pipeline_state_ = [gpu.device() newRenderPipelineStateWithDescriptor:pipeline_desc
//                                                                      error:&err];
//       [pipeline_state_ retain];

//       if (err != nullptr) {
//          const char *message = [err.localizedDescription UTF8String];
//          throw std::runtime_error(std::format("error creating render pipeline state: {}", message));
//       }
//    }
// }

// Pipeline::Pipeline(Pipeline &&old) : pipeline_state_(old.pipeline_state_) {
//    old.pipeline_state_ = nil;
// }

// Pipeline::~Pipeline() {
//    if (pipeline_state_ != nil) {
//       [pipeline_state_ release];
//    }
// }
