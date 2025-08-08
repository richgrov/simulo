#ifndef SIMULO_RUNTIME_CAMERA_MJPG_H
#define SIMULO_RUNTIME_CAMERA_MJPG_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void to_rgbu8(const unsigned char *mjpg_data, unsigned char *rgb_data, int width, int height);
void to_rgbf32(const unsigned char *mjpg_data, float *rgb_data);

#ifdef __cplusplus
}
#endif

#endif