#pragma once

#include <atomic>
#include <memory>
#include <optional>
#include <shared_mutex>
#include <thread>
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

   void set_running(bool run);

   std::vector<Detection> latest_detections() {
      std::shared_lock lock(detection_lock_);
      return latest_detections_;
   }

private:
   void detect();

   std::unique_ptr<cv::VideoCapture> capture_;
   std::unique_ptr<cv::dnn::dnn4_v20241223::Net> model_;
   std::atomic<bool> running_;
   std::optional<std::thread> thread_;

   std::shared_mutex detection_lock_;
   std::vector<Detection> latest_detections_;
};

} // namespace simulo
