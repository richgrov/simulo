#pragma once

#ifdef __cplusplus
extern "C" {
#endif

struct ImageData;

struct ImageData *load_image_from_memory(const unsigned char *data, int data_len);
int get_image_width(struct ImageData *img);
int get_image_height(struct ImageData *img);
const unsigned char *get_image_data(struct ImageData *img);
void free_image_data(struct ImageData *img);

#ifdef __cplusplus
}
#endif