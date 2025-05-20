#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void run(void);

const unsigned char *pose_model_bytes(void);
size_t pose_model_len(void);

#ifdef __cplusplus
}
#endif
