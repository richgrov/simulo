#include "perception.h"

#include <cassert>
#include <mutex>
#include <shared_mutex>
#include <stdexcept>

#include <opencv2/calib3d.hpp>
#include <opencv2/core/types.hpp>
#include <opencv2/dnn/dnn.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/videoio.hpp>
#include <thread>

#include "pose_model.h"

using namespace simulo;

namespace {

static const cv::Size kInputImageSize(640, 640);
static constexpr int kBoxChannels = 56;
static constexpr int kNumBoxes = 8400;
static constexpr float kScoreThreshold = 0.7;
static constexpr float kNmsThreshold = 0.5;

static constexpr float kCalibrationMinContourArea = 0.1f;
static constexpr float kPolyApproxEpsilon = 0.02f;

// Given a vector of B*C*N, return a N*C matrix
cv::Mat postprocess(const std::vector<cv::Mat> &outputs) {
#ifdef SIMULO_DEBUG
   assert(outputs.size() == 1);
   assert(outputs[0].size[0] == 1);
   assert(outputs[0].size[1] == kBoxChannels);
   assert(outputs[0].size[2] == kNumBoxes);
#endif

   return outputs[0].reshape(1, kBoxChannels).t();
}

// Sorts points for a warped quad in TL, TR, BL, BR order
void sort_quadrangle_points(std::vector<cv::Point2f> &points) {
   std::sort(points.begin(), points.end(), [](cv::Point2f a, cv::Point2f b) {
      return a.y + a.x < b.y + b.x;
   });

   if (points[1].x < points[2].x) {
      std::swap(points[1], points[2]);
   }
}

} // namespace

Perception::Perception() : capture_(0), model_(get_pose_model()) {}

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

   static thread_local cv::Mat gray, edges;
   cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
   cv::Canny(gray, edges, 30, 40);

   static thread_local cv::Mat blurred_edges;
   cv::GaussianBlur(edges, blurred_edges, cv::Size(5, 5), 0);

   std::vector<std::vector<cv::Point>> contours;
   cv::findContours(blurred_edges, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

   float min_area = frame.rows * frame.cols * kCalibrationMinContourArea;
   for (const auto &contour : contours) {
      double area = cv::contourArea(contour);
      if (area < min_area) {
         continue;
      }

      double epsilon = kPolyApproxEpsilon * cv::arcLength(contour, true);
      cv::approxPolyDP(contour, calibration_quad_, epsilon, true);

      if (calibration_quad_.size() != 4) {
         continue;
      }

      sort_quadrangle_points(calibration_quad_);

      static std::vector<cv::Point2f> dst_points = {
          cv::Point2f(0.0f, 0.0f), // TL
          cv::Point2f(1.0f, 0.0f), // TR
          cv::Point2f(0.0f, 1.0f), // BL
          cv::Point2f(1.0f, 1.0f), // BR
      };

      perspective_transform_ = cv::getPerspectiveTransform(calibration_quad_, dst_points);
      calibrated_ = true;
      return true;
   }

   return false;
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
      detection.points[i].x = transformed_keypoints[i].x;
      detection.points[i].y = transformed_keypoints[i].y;
   }
}

void Perception::detect() {
   static thread_local cv::Mat capture_mat;
   if (!capture_.read(capture_mat)) {
      throw std::runtime_error("Could not read from camera");
   }

   if (!calibrated_) {
      detect_calibration_marker(capture_mat);
   }

   static thread_local cv::Mat blob;
   cv::dnn::blobFromImage(
       capture_mat, blob, 1.0 / 255.0, kInputImageSize, cv::Scalar(), true, false
   );
   model_.setInput(blob);

   static thread_local std::vector<cv::Mat> outputs;
   model_.forward(outputs, model_.getUnconnectedOutLayersNames());

   cv::Mat output = postprocess(outputs);

   std::vector<cv::Rect> boxes;
   std::vector<float> scores;
   std::vector<std::vector<Keypoint>> detection_points;

   for (int box_idx = 0; box_idx < kNumBoxes; box_idx++) {
      float *box_props = output.row(box_idx).ptr<float>();

      float score = box_props[4];
      if (score < kScoreThreshold) {
         continue;
      }

      scores.push_back(score);

      float x_center = box_props[0];
      float y_center = box_props[1];
      float width = box_props[2];
      float height = box_props[3];
      boxes.emplace_back(x_center - 0.5f * width, y_center - 0.5f * height, width, height);

      std::vector<Keypoint> points;
      for (int keypoint_idx = 0; keypoint_idx < 17; keypoint_idx++) {
         points.emplace_back(Keypoint{
             .x = box_props[5 + keypoint_idx * 3],
             .y = box_props[5 + keypoint_idx * 3 + 1],
             .visibility = box_props[5 + keypoint_idx * 3 + 2],
         });
      }

      detection_points.push_back(points);
   }

   std::vector<int> filtered_indices;
   cv::dnn::NMSBoxes(boxes, scores, kScoreThreshold, kNmsThreshold, filtered_indices);

   std::vector<Detection> result{};
   for (int i : filtered_indices) {
      cv::Rect2i box = boxes[i];

      float x = rescale(box.x, kInputImageSize.width, capture_mat.cols);
      float y = rescale(box.y, kInputImageSize.height, capture_mat.rows);
      float w = rescale(box.width, kInputImageSize.width, capture_mat.cols);
      float h = rescale(box.height, kInputImageSize.height, capture_mat.rows);

      for (auto &kp : detection_points[i]) {
         kp.x = rescale(kp.x, kInputImageSize.width, capture_mat.cols);
         kp.y = rescale(kp.y, kInputImageSize.height, capture_mat.rows);
      }

      Detection detection{
          .x = x,
          .y = y,
          .width = w,
          .height = h,
          .confidence = scores[i],
          .points = detection_points[i]
      };

      if (calibrated_) {
         apply_calibration_transform(detection);
      }

      result.push_back(detection);
   }

   std::unique_lock lock(detection_lock_);
   latest_detections_ = std::move(result);
}

void Perception::set_running(bool run) {
   running_ = run;

   if (run) {
      thread_ = std::thread([this] {
         while (running_) {
            detect();
         }
      });
   } else {
      if (thread_.joinable()) {
         thread_.join();
      }
   }
}
