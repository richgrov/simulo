#pragma once

#include <atomic>
#include <optional>
#include <shared_mutex>
#include <thread>
#include <vector>

#include <opencv2/core/mat.hpp>
#include <opencv2/dnn.hpp>
#include <opencv2/videoio.hpp>

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

   bool is_calibrated() const {
      return calibrated_;
   }

private:
   void detect();
   bool detect_calibration_marker(cv::Mat &frame);
   void apply_calibration_transform(Detection &detection);

   cv::VideoCapture capture_;
   cv::dnn::Net model_;
   std::atomic<bool> running_;
   std::optional<std::thread> thread_;

   std::shared_mutex detection_lock_;
   std::vector<Detection> latest_detections_;

   std::atomic<bool> calibrated_{false};
   std::vector<cv::Point2f> calibration_quad_;
   cv::Mat perspective_transform_;
};

} // namespace simulo
