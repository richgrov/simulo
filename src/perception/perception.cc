#include "perception.h"

#include <cassert>
#include <cstring>
#include <mutex>
#include <shared_mutex>
#include <stdexcept>

#define ORT_NO_EXCEPTIONS
#include <onnxruntime_cxx_api.h>
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

Ort::SessionOptions ort_session_options() {
   Ort::SessionOptions opts;
#ifdef __APPLE__
   opts.AppendExecutionProvider("CoreML");
#endif
   return opts;
}

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

Perception::Perception(std::shared_ptr<const Ort::Env> ort_env, int id)
    : id_{id},
      ort_env_{ort_env},
      ort_session_{
          Ort::Session(*ort_env_.get(), pose_model_bytes(), pose_model_len(), ort_session_options())
      },
      ort_mem_info_{Ort::MemoryInfo::CreateCpu(OrtDeviceAllocator, OrtMemTypeCPU)},
      ort_allocator_{ort_session_, ort_mem_info_},
      ort_input_{Ort::Value::CreateTensor(
          ort_allocator_, kModelInputShape, 4, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT
      )},
      ort_output_{Ort::Value::CreateTensor(
          ort_allocator_, kModelOutputShape, 3, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT
      )} {

   std::cout << "ONNX Version: " << Ort::GetVersionString() << '\n';
}

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

void Perception::detect() {
   static thread_local cv::Mat capture_mat;
   if (!capture_.read(capture_mat)) {
      throw std::runtime_error("Could not read from camera");
   }

   if (!calibrated_) {
      if (!detect_calibration_marker(capture_mat)) {
         return;
      }
   }

   static thread_local cv::Mat blob;
   cv::dnn::blobFromImage(
       capture_mat, blob, 1.0 / 255.0, kInputImageSize, cv::Scalar(), true, false
   );
   std::memcpy(ort_input_.GetTensorMutableData<float>(), blob.data, blob.total() * blob.elemSize());

   Ort::RunOptions run_opts;
   ort_session_.Run(run_opts, kModelInputNames, &ort_input_, 1, kModelOutputNames, &ort_output_, 1);

   Array2d<float, kNumBoxes> data(ort_output_.GetTensorData<float>());

   std::vector<cv::Rect> boxes;
   std::vector<float> scores;
   std::vector<std::vector<Keypoint>> detection_points;

   for (int box_idx = 0; box_idx < kNumBoxes; box_idx++) {
      // float *box_props = output.row(box_idx).ptr<float>();
      float score = data.get(box_idx, 4);
      if (score < kScoreThreshold) {
         continue;
      }

      scores.push_back(score);

      float x_center = data.get(box_idx, 0);
      float y_center = data.get(box_idx, 1);
      float width = data.get(box_idx, 2);
      float height = data.get(box_idx, 3);
      boxes.emplace_back(x_center - 0.5f * width, y_center - 0.5f * height, width, height);

      std::vector<Keypoint> points;
      for (int keypoint_idx = 0; keypoint_idx < 17; keypoint_idx++) {
         points.emplace_back(Keypoint{
             .x = data.get(box_idx, 5 + keypoint_idx * 3),
             .y = data.get(box_idx, 5 + keypoint_idx * 3 + 1),
             .visibility = data.get(box_idx, 5 + keypoint_idx * 3 + 2),
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
