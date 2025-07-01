#include <memory>
#include <span>

#include <vulkan/vulkan_core.h>

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

Window *create_window(VkInstance vk_instance, const char *title) {
   std::unique_ptr<Window> window = simulo::create_window(vk_instance, title);
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

// #ifdef VKAD_APPLE
// Renderer *create_renderer(Gpu *gpu, const Window *window) {
// return new Renderer(*gpu, window->layer_pixel_format(), window->metal_layer());
// #else
Renderer *create_renderer(VkInstance vk_instance, const Window *window) {
   return new Renderer(vk_instance, window->surface(), window->width(), window->height());
   // #endif
}

void destroy_renderer(Renderer *renderer) {
   delete renderer;
}

Gpu *create_gpu(void) {
   return new Gpu();
}

void destroy_gpu(Gpu *gpu) {
   delete gpu;
}

uint32_t create_ui_material(Renderer *renderer, uint32_t image, float r, float g, float b) {
   return renderer->create_material<UiUniform>(
       renderer->pipelines().ui, {
                                     {"image", static_cast<RenderImage>(image)},
                                     {"color", Vec3{r, g, b}},
                                 }
   );
}

uint32_t create_mesh_material(Renderer *renderer, float r, float g, float b) {
   return renderer->create_material<ModelUniform>(
       renderer->pipelines().mesh, {
                                       {"color", Vec3{r, g, b}},
                                   }
   );
}

uint32_t create_mesh(
    Renderer *renderer, uint8_t *vertex_data, size_t vertex_size, uint16_t *index_data,
    size_t index_count
) {
   std::span<uint8_t> vert_span(vertex_data, vertex_size);
   std::span<Renderer::IndexBufferType> index_span(
       reinterpret_cast<Renderer::IndexBufferType *>(index_data), index_count
   );
   return static_cast<uint32_t>(renderer->create_mesh(vert_span, index_span));
}

void delete_mesh(Renderer *renderer, uint32_t mesh_id) {
   renderer->delete_mesh(static_cast<RenderMesh>(mesh_id));
}

uint32_t
add_object(Renderer *renderer, uint32_t mesh_id, const float *transform, uint32_t material_id) {
   Mat4 mat4_transform;
   std::memcpy(&mat4_transform, transform, sizeof(Mat4));

   return static_cast<uint32_t>(renderer->add_object(
       static_cast<RenderMesh>(mesh_id), mat4_transform, static_cast<RenderMaterial>(material_id)
   ));
}

void delete_object(Renderer *renderer, uint32_t object_id) {
   renderer->delete_object(static_cast<RenderObject>(object_id));
}

uint32_t create_image(Renderer *renderer, uint8_t *img_data, int width, int height) {
   std::span<uint8_t> data_span(img_data, width * height);
   return static_cast<uint32_t>(renderer->create_image(data_span, width, height));
}

void set_object_transform(Renderer *renderer, uint32_t object_id, const float *transform) {
   Mat4 mat4_transform;
   std::memcpy(&mat4_transform, transform, sizeof(Mat4));
   renderer->set_object_transform(static_cast<RenderObject>(object_id), mat4_transform);
}

bool render(
    Renderer *renderer, const float *ui_view_projection, const float *world_view_projection
) {
   Mat4 ui_mat;
   Mat4 world_mat;
   std::memcpy(&ui_mat, ui_view_projection, sizeof(Mat4));
   std::memcpy(&world_mat, world_view_projection, sizeof(Mat4));

   return renderer->render(ui_mat, world_mat);
}

#ifndef VKAD_APPLE
void recreate_swapchain(Renderer *renderer, Window *window) {
   renderer->recreate_swapchain(window->width(), window->height(), window->surface());
}
#endif

void wait_idle(Renderer *renderer) {
   renderer->wait_idle();
}
