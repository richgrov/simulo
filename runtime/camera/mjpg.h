#ifndef SIMULO_RUNTIME_CAMERA_MJPG_H
#define SIMULO_RUNTIME_CAMERA_MJPG_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

bool to_rgbu8(unsigned char *mjpg_data, unsigned char *rgb_data, int width, int height, int data_size);
bool to_rgbf32(unsigned char *mjpg_data, float *rgb_data, int data_size);

#ifdef __cplusplus
}
#endif

#endif