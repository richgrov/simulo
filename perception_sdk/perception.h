#pragma once

#include <memory>
#include <vector>

namespace cv {

class VideoCapture;

namespace dnn::dnn4_v20241223 {

class Net;

}

} // namespace cv

namespace simulo {

class Perception {
public:
   struct Keypoint {
      float x;
      float y;
      float visibility;
   };

   struct Detection {
      float x;
      float y;
      float width;
      float height;
      float confidence;
      std::vector<Keypoint> points;
   };

   Perception();

   ~Perception();

   std::vector<Detection> detect();

private:
   std::unique_ptr<cv::VideoCapture> capture_;
   std::unique_ptr<cv::dnn::dnn4_v20241223::Net> model_;
};

} // namespace simulo
