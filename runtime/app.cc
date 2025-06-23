#include "ffi.h"
#include "render/renderer.h"
#include "window/window.h"

using namespace simulo;

Renderer *create_renderer(Gpu *gpu, const Window *window) {
   return new Renderer(*gpu, window->layer_pixel_format(), window->metal_layer());
}

void destroy_renderer(Renderer *renderer) {
   delete renderer;
}
