#pragma once

#include "gpu/gpu.h"

#ifdef __OBJC__
#include <Metal/Metal.h>
#endif

namespace vkad {

class Pipeline {
public:
   Pipeline(const Gpu &gpu, void *pixel_format);
   ~Pipeline();

#ifdef __OBJC__
   id<MTLRenderPipelineState> _Nonnull pipeline_state() const {
      return pipeline_state_;
   }
#endif

private:
#ifdef __OBJC__
   id<MTLRenderPipelineState> _Nonnull pipeline_state_;
#else
   void *pipeline_state_;
#endif
};

} // namespace vkad
