#pragma once

#ifdef __cplusplus
extern "C" {
#endif

struct ImageData;

ImageData* load_image_from_memory(const unsigned char* data, int data_len);
int get_image_width(ImageData* img);
int get_image_height(ImageData* img);
const unsigned char* get_image_data(ImageData* img);
void free_image_data(ImageData* img);

#ifdef __cplusplus
}
#endif