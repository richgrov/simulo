#include "ffi.h"
#include "render/renderer.h"
#include "util/os_detect.h"
#include "window/window.h"

using namespace simulo;

Renderer *create_renderer(Gpu *gpu, const Window *window) {
#ifdef VKAD_APPLE
   return new Renderer(*gpu, window->layer_pixel_format(), window->metal_layer());
#else
   return new Renderer(gpu_, window_->surface(), window_->width(), window_->height()),
#endif
}

void destroy_renderer(Renderer *renderer) {
   delete renderer;
}
