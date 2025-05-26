#include "perception.h"

#include <cassert>
#include <cstring>
#include <mutex>
#include <shared_mutex>
#include <stdexcept>

#include <opencv2/calib3d.hpp>
#include <opencv2/core.hpp>
#include <opencv2/core/types.hpp>
#include <opencv2/dnn/dnn.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/videoio.hpp>

#include "ffi.h"

using namespace simulo;

namespace {

static const cv::Size kInputImageSize(640, 640);
static constexpr int kBoxChannels = 56;
static constexpr int kNumBoxes = 8400;
static const char *kModelInputNames[] = {"images"};
static const char *kModelOutputNames[] = {"output0"};
static const int64_t kModelInputShape[] = {1, 3, kInputImageSize.width, kInputImageSize.height};
static const int64_t kModelOutputShape[] = {1, kBoxChannels, kNumBoxes};
static constexpr float kScoreThreshold = 0.7;
static constexpr float kNmsThreshold = 0.5;

static const cv::Size kChessboardPatternSize(9, 5);

template <class T, size_t Width> class Array2d {
public:
   Array2d(const T *data) : data_{data} {}

   T get(size_t x, size_t y) {
      return data_[y * Width + x];
   }

private:
   const T *data_;
};

} // namespace

float rescale(float f, float from_range, float to_range) {
   return f / from_range * to_range;
}

Perception::~Perception() {
   set_running(false);
}

bool Perception::detect_calibration_marker(cv::Mat &frame) {
   if (calibrated_) {
      return true;
   }

   static thread_local cv::Mat gray;
   cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);

   std::vector<cv::Point2f> corners;
   bool found =
       cv::findChessboardCornersSB(gray, kChessboardPatternSize, corners, cv::CALIB_CB_EXHAUSTIVE);

   {
      std::unique_lock lock(detection_lock_);
      cv::Mat debug_frame = frame.clone();
      cv::drawChessboardCorners(debug_frame, kChessboardPatternSize, corners, found);
      latest_frame_ = debug_frame;
   }

   if (!found) {
      return false;
   }

   cv::Point2f tl = corners[0];
   cv::Point2f tr = corners[kChessboardPatternSize.width - 1];
   cv::Point2f bl = corners[corners.size() - kChessboardPatternSize.width];
   cv::Point2f br = corners[corners.size() - 1];

   std::vector<cv::Point2f> src_points = {tl, tr, bl, br};
   static std::vector<cv::Point2f> dst_points = {
       cv::Point2f(0.0f, 0.0f), // TL
       cv::Point2f(1.0f, 0.0f), // TR
       cv::Point2f(0.0f, 1.0f), // BL
       cv::Point2f(1.0f, 1.0f), // BR
   };

   perspective_transform_ = cv::getPerspectiveTransform(src_points, dst_points);
   calibrated_ = true;
   return true;
}

void Perception::apply_calibration_transform(Detection &detection) {
   if (!calibrated_) {
      return;
   }

   std::vector<cv::Point2f> keypoints;
   for (const auto &point : detection.points) {
      keypoints.push_back(cv::Point2f(point.x, point.y));
   }

   std::vector<cv::Point2f> transformed_keypoints;
   cv::perspectiveTransform(keypoints, transformed_keypoints, perspective_transform_);

   for (size_t i = 0; i < detection.points.size(); i++) {
      float x_shrink = (kChessboardPatternSize.width - 1.f) / (kChessboardPatternSize.width + 1);
      float y_shrink = (kChessboardPatternSize.height - 1.f) / (kChessboardPatternSize.height + 1);
      int x_shift = 1.f / (kChessboardPatternSize.width + 1);
      int y_shift = 1.f / (kChessboardPatternSize.height + 1);
      detection.points[i].x = transformed_keypoints[i].x * x_shrink + x_shift;
      detection.points[i].y = transformed_keypoints[i].y * y_shrink + y_shift;
   }
}

void Perception::detect() {}

void Perception::set_running(bool run) {
   if (running_ && run) {
      return;
   }

   running_ = run;

   if (run) {
      capture_.open(0);
      thread_ = std::thread([this] {
         while (running_) {
            detect();
         }
      });
   } else {
      if (thread_.joinable()) {
         thread_.join();
         capture_.release();
      }
   }
}

void Perception::debug_window() {
   std::shared_lock lock(detection_lock_);

   cv::Mat display = cv::Mat(1080, 1920, CV_8UC3, cv::Scalar(0, 0, 0)); // Start with black

   if (!calibrated_) {
      // Draw a chessboard pattern if not calibrated
      int board_width = kChessboardPatternSize.width + 1;
      int board_height = kChessboardPatternSize.height + 1;
      int square_width = display.cols / board_width;
      int square_height = display.rows / board_height;

      for (int i = 0; i < board_height; ++i) {
         for (int j = 0; j < board_width; ++j) {
            if ((i + j) % 2 == 0) { // White squares
               cv::Rect square(j * square_width, i * square_height, square_width, square_height);
               cv::rectangle(display, square, cv::Scalar(255, 255, 255), cv::FILLED);
            }
         }
      }
   } else {
      // Draw detections only if calibrated
      for (const Detection &det : latest_detections_) {
         for (Keypoint point : det.points) {
            int x = point.x * display.cols;
            int y = point.y * display.rows;
            cv::circle(display, cv::Point(x, y), 8, cv::Scalar(255, 255, 255), -1);
         }

#define POINT(n) cv::Point(det.points[n].x *display.cols, det.points[n].y *display.rows)
         cv::line(display, POINT(9), POINT(7), cv::Scalar(255, 255, 255), 4);
         cv::line(display, POINT(7), POINT(5), cv::Scalar(255, 255, 255), 4);
         cv::line(display, POINT(10), POINT(8), cv::Scalar(255, 255, 255), 4);
         cv::line(display, POINT(8), POINT(6), cv::Scalar(255, 255, 255), 4);
         cv::line(display, POINT(6), POINT(5), cv::Scalar(255, 255, 255), 4);
      }
   }

   if (!latest_frame_.empty()) {
      cv::imshow("Debug", latest_frame_);
   }

   cv::imshow("Display", display);
   cv::pollKey();
}
