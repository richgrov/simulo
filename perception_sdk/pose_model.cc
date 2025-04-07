#include "pose_model.h"

#include <opencv2/dnn.hpp>

#include "onnx_exporter/yolo11n-pose.onnx.h"

namespace simulo {

cv::dnn::Net get_pose_model() {
   cv::dnn::Net model = cv::dnn::readNetFromONNX(
       reinterpret_cast<const char *>(onnx_exporter_yolo11n_pose_onnx),
       onnx_exporter_yolo11n_pose_onnx_len
   );

   model.setPreferableBackend(cv::dnn::DNN_BACKEND_OPENCV);
   model.setPreferableTarget(cv::dnn::DNN_TARGET_CPU);
   return model;
}

} // namespace simulo
