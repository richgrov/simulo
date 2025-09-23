#include "opencv_image.h"

#include <opencv2/opencv.hpp>

#include <cstring>
#include <vector>

extern "C" {

unsigned char *
load_image_from_memory(const unsigned char *data, int data_len, int *out_width, int *out_height) {
   std::vector<unsigned char> buffer(data, data + data_len);
   cv::Mat image = cv::imdecode(buffer, cv::IMREAD_UNCHANGED);

   if (image.empty()) {
      return nullptr;
   }

   cv::Mat rgba_image;
   if (image.channels() == 3) {
      cv::cvtColor(image, rgba_image, cv::COLOR_BGR2RGBA);
   } else if (image.channels() == 4) {
      cv::cvtColor(image, rgba_image, cv::COLOR_BGRA2RGBA);
   } else if (image.channels() == 1) {
      cv::cvtColor(image, rgba_image, cv::COLOR_GRAY2RGBA);
   } else {
      return nullptr;
   }

   cv::Mat flipped;
   cv::flip(rgba_image, flipped, 0);

   *out_width = flipped.cols;
   *out_height = flipped.rows;
   size_t bytes = flipped.total() * flipped.channels();
   unsigned char *result = new unsigned char[bytes];
   if (!result) {
      return nullptr;
   }
   std::memcpy(result, flipped.data, bytes);

   return result;
}

void free_image_data(const unsigned char *bytes) {
   delete[] bytes;
}
}