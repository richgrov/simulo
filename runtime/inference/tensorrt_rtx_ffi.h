#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    float box[4];
    float score;
    float keypoints[17 * 3];
} RtxDetection;

void* trt_rtx_create(const char* model_path);
void trt_rtx_destroy(void* ctx);
float* trt_rtx_input_buffer(void* ctx, int index);
size_t trt_rtx_run(void* ctx, int index, RtxDetection* dets, size_t max_dets);

#ifdef __cplusplus
}
#endif
