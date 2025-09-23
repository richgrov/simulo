#include <opencv2/opencv.hpp>
#include <vector>

extern "C" {

struct ImageData {
   int width;
   int height;
   std::vector<unsigned char> data;
};

ImageData *load_image_from_memory(const unsigned char *data, int data_len) {
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

   auto *result = new ImageData();
   result->width = flipped.cols;
   result->height = flipped.rows;
   result->data.resize(flipped.total() * flipped.channels());
   std::memcpy(result->data.data(), flipped.data, result->data.size());

   return result;
}

int get_image_width(ImageData *img) {
   return img ? img->width : 0;
}

int get_image_height(ImageData *img) {
   return img ? img->height : 0;
}

const unsigned char *get_image_data(ImageData *img) {
   return img ? img->data.data() : nullptr;
}

void free_image_data(ImageData *img) {
   delete img;
}
}