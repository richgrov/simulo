#include "pose_model.h"

#include <opencv2/dnn.hpp>

#include "yolo11n_pose.h"

namespace simulo {

Ort::Session create_pose_session(const Ort::Env &env, const Ort::SessionOptions &opts) {
   return Ort::Session(env, yolo11n_pose, yolo11n_pose_len, opts);
}

} // namespace simulo
