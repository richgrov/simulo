#pragma once

#include "util/os_detect.h"
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void run(void);

const unsigned char *pose_model_bytes(void);
size_t pose_model_len(void);

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

#ifdef __cplusplus
}
#endif
