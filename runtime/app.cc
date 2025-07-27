#include <memory>
#include <span>

#include "ffi.h"
#include "gpu/gpu.h"
#include "math/matrix.h"
#include "math/vector.h"
#include "render/model.h"
#include "render/renderer.h"
#include "render/ui.h"
#include "util/os_detect.h"
#include "window/window.h"

using namespace simulo;

Window *create_window(const Gpu *gpu, const char *title) {
   std::unique_ptr<Window> window = simulo::create_window(*gpu, title);
   return window.release();
}

void destroy_window(Window *window) {
   delete window;
}

bool poll_window(Window *window) {
   return window->poll();
}

void set_capture_mouse(Window *window, bool capture) {
   window->set_capture_mouse(capture);
}

void request_close_window(Window *window) {
   window->request_close();
}

int get_window_width(const Window *window) {
   return window->width();
}

int get_window_height(const Window *window) {
   return window->height();
}

int get_mouse_x(const Window *window) {
   return window->mouse_x();
}

int get_mouse_y(const Window *window) {
   return window->mouse_y();
}

int get_delta_mouse_x(const Window *window) {
   return window->delta_mouse_x();
}

int get_delta_mouse_y(const Window *window) {
   return window->delta_mouse_y();
}

bool is_left_clicking(const Window *window) {
   return window->left_clicking();
}

bool is_key_down(const Window *window, uint8_t key_code) {
   return window->is_key_down(key_code);
}

bool key_just_pressed(const Window *window, uint8_t key_code) {
   return window->key_just_pressed(key_code);
}

const char *get_typed_chars(const Window *window) {
   std::string_view chars = window->typed_chars();
   static thread_local char buffer[64];
   size_t length = std::min(chars.length(), sizeof(buffer) - 1);
   memcpy(buffer, chars.data(), length);
   buffer[length] = '\0';
   return buffer;
}

int get_typed_chars_length(const Window *window) {
   return static_cast<int>(window->typed_chars().length());
}

#ifdef VKAD_APPLE

Renderer *create_renderer(Gpu *gpu, const Window *window) {
   return new Renderer(*gpu, window->layer_pixel_format(), window->metal_layer());
}

#else

void *get_window_surface(const Window *window) {
   return reinterpret_cast<void *>(window->surface());
}

Renderer *create_renderer(Gpu *gpu, const Window *window) {
   return new Renderer(*gpu, window->surface(), window->width(), window->height());
}

#endif

void destroy_renderer(Renderer *renderer) {
   delete renderer;
}

Gpu *create_gpu(void) {
   return new Gpu();
}

void destroy_gpu(Gpu *gpu) {
   delete gpu;
}

uint32_t create_image(Renderer *renderer, uint8_t *img_data, int width, int height) {
   std::span<uint8_t> data_span(img_data, width * height * 4);
   return static_cast<uint32_t>(renderer->create_image(data_span, width, height));
}

void wait_idle(Renderer *renderer) {
   renderer->wait_idle();
}
