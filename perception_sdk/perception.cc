#include "perception.h"

#include <cassert>
#include <mutex>
#include <stdexcept>

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

} // namespace

Perception::Perception() : capture_(0), model_(get_pose_model()) {}

float rescale(float f, float from_range, float to_range) {
   return f / from_range * to_range;
}

Perception::~Perception() {
   set_running(false);
}

void Perception::detect() {
   cv::Mat capture_mat;
   if (!capture_.read(capture_mat)) {
      throw std::runtime_error("Could not read from camera");
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

      result.emplace_back(Detection{
          .x = x,
          .y = y,
          .width = w,
          .height = h,
          .confidence = scores[i],
          .points = detection_points[i]
      });

      cv::rectangle(capture_mat, cv::Rect(x, y, w, h), cv::Scalar(0, 255, 0), 2);
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
      thread_->join();
   }
}
