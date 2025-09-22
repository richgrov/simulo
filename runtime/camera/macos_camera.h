#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __OBJC__
#import <AVFoundation/AVFoundation.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

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

typedef enum {
   ErrorNone,
   ErrorNoCamera,
   ErrorNoPermission,
   ErrorCannotCapture,
   ErrorCannotCreateCapture,
   ErrorCannotAddInput,
   ErrorCannotAddOutput,
} CameraError;

CameraError init_camera(
    Camera *camera, unsigned char *buf_a, unsigned char *buf_b, const char *device_id,
    size_t device_id_len
);
void destroy_camera(Camera *camera);
void set_camera_float_mode(Camera *camera, float *buf_a, float *buf_b);
int swap_camera_buffers(Camera *camera);

#ifdef __cplusplus
}
#endif