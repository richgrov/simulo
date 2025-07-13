#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "util/os_detect.h"

#if defined(VKAD_APPLE) && defined(__OBJC__)
#include <AVFoundation/AVFoundation.h>
#import <Metal/Metal.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

void run(void);

const unsigned char *arial_bytes(void);
size_t arial_len(void);

#if defined(VKAD_WINDOWS) || defined(VKAD_LINUX)
const unsigned char *text_vertex_bytes(void);
size_t text_vertex_len(void);
const unsigned char *text_fragment_bytes(void);
size_t text_fragment_len(void);

const unsigned char *model_vertex_bytes(void);
size_t model_vertex_len(void);
const unsigned char *model_fragment_bytes(void);
size_t model_fragment_len(void);
#endif

#ifdef VKAD_APPLE

#ifdef __OBJC__
@class SimuloCameraDelegate;
#endif

typedef struct {
#ifdef __OBJC__
   AVCaptureSession *session;
   SimuloCameraDelegate *delegate;
#else
   void *session;
   void *delegate;
#endif
} Camera;

bool init_camera(Camera *camera, unsigned char *buf_a, unsigned char *buf_b);
void destroy_camera(Camera *camera);
void set_camera_float_mode(Camera *camera, float *buf_a, float *buf_b);
int swap_camera_buffers(Camera *camera);

#endif

#ifdef __cplusplus

namespace cv {
class Mat;
}
using OpenCvMat = cv::Mat;

namespace simulo {
class Renderer;
class Gpu;
class Window;
} // namespace simulo
using Renderer = simulo::Renderer;
using Gpu = simulo::Gpu;
using Window = simulo::Window;

#else

struct CvMat;
typedef struct CvMat OpenCvMat;

struct SimuloRenderer;
typedef struct SimuloRenderer Renderer;

struct SimuloGpu;
typedef struct SimuloGpu Gpu;

struct SimuloWindow;
typedef struct SimuloWindow Window;

#endif

typedef struct {
   double data[9];
} FfiMat3;

typedef uint16_t IndexBufferType;

typedef struct {
#ifdef __OBJC__
   id<MTLBuffer> uniform_buffer;
#else
   void *uniform_buffer;
#endif
   int image;
} Material;

typedef struct {
#if defined(VKAD_APPLE) && defined(__OBJC__)
   id<MTLBuffer> buffer;
#else
   void *buffer;
#endif
   size_t indices_start;
   IndexBufferType num_indices;
} Mesh;

OpenCvMat *create_opencv_mat(int rows, int cols);
void destroy_opencv_mat(OpenCvMat *mat);
unsigned char *get_opencv_mat_data(OpenCvMat *mat);
bool find_chessboard(OpenCvMat *mat, int pattern_width, int pattern_height, FfiMat3 *out_transform);

Renderer *create_renderer(Gpu *gpu, const Window *window);
void destroy_renderer(Renderer *renderer);
Material create_ui_material(Renderer *renderer, uint32_t image, float r, float g, float b);
uint32_t create_mesh_material(Renderer *renderer, float r, float g, float b);
Mesh create_mesh(
    Renderer *renderer, uint8_t *vertex_data, size_t vertex_data_size, IndexBufferType *index_data,
    size_t index_count
);
void delete_mesh(Renderer *renderer, Mesh *mesh);
uint32_t
add_object(Renderer *renderer, uint32_t mesh_id, const float *transform, uint32_t material_id);
void delete_object(Renderer *renderer, uint32_t object_id);
uint32_t create_image(Renderer *renderer, uint8_t *img_data, int width, int height);
void set_object_transform(Renderer *renderer, uint32_t object_id, const float *transform);
bool render(
    Renderer *renderer, const float *ui_view_projection, const float *world_view_projection
);

bool begin_render(Renderer *renderer);
void set_pipeline(Renderer *renderer, uint32_t pipeline_id);
void set_material(Renderer *renderer, Material *material);
void set_mesh(Renderer *renderer, Mesh *mesh);
void render_object(Renderer *renderer, const float *transform);
void end_render(Renderer *renderer);

#ifndef VKAD_APPLE
void recreate_swapchain(Renderer *renderer, Window *window);
#endif
void wait_idle(Renderer *renderer);

Gpu *create_gpu(void);
void destroy_gpu(Gpu *gpu);

Window *create_window(const Gpu *gpu, const char *title);
void destroy_window(Window *window);
bool poll_window(Window *window);
void set_capture_mouse(Window *window, bool capture);
void request_close_window(Window *window);
int get_window_width(const Window *window);
int get_window_height(const Window *window);
int get_mouse_x(const Window *window);
int get_mouse_y(const Window *window);
int get_delta_mouse_x(const Window *window);
int get_delta_mouse_y(const Window *window);
bool is_left_clicking(const Window *window);
bool is_key_down(const Window *window, uint8_t key_code);
bool key_just_pressed(const Window *window, uint8_t key_code);
const char *get_typed_chars(const Window *window);
int get_typed_chars_length(const Window *window);

#ifdef __cplusplus
}
#endif
