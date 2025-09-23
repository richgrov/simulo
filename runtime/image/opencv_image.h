#pragma once

#ifdef __cplusplus
extern "C" {
#endif

unsigned char *
load_image_from_memory(const unsigned char *data, int data_len, int *out_width, int *out_height);
void free_image_data(const unsigned char *bytes);

#ifdef __cplusplus
}
#endif