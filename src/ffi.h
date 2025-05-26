#pragma once

#include <stdbool.h>
#include <stddef.h>

#include "util/os_detect.h"

#if defined(VKAD_APPLE) && defined(__OBJC__)
#include <AVFoundation/AVFoundation.h>
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

#endif

bool init_camera(Camera *camera, unsigned char *out);
void destroy_camera(Camera *camera);
void set_camera_float_mode(Camera *camera, float *out);
void lock_camera_frame(Camera *camera);
void unlock_camera_frame(Camera *camera);

#ifdef __cplusplus

namespace cv {
class Mat;
}
using OpenCvMat = cv::Mat;

namespace simulo {
class Renderer;
class Gpu;
} // namespace simulo
using Renderer = simulo::Renderer;
using Gpu = simulo::Gpu;

#else

struct CvMat;
typedef struct CvMat OpenCvMat;

struct SimuloRenderer;
typedef struct SimuloRenderer Renderer;

struct SimuloGpu;
typedef struct SimuloGpu Gpu;

#endif

OpenCvMat *create_opencv_mat(int rows, int cols);
void destroy_opencv_mat(OpenCvMat *mat);
unsigned char *get_opencv_mat_data(OpenCvMat *mat);
bool find_chessboard(OpenCvMat *mat, int pattern_width, int pattern_height);

Renderer *create_renderer(void);
void destroy_renderer(Renderer *renderer);

Gpu *create_gpu(void);
void destroy_gpu(Gpu *gpu);

#ifdef __cplusplus
}
#endif
