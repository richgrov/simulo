#pragma once

#include <onnxruntime_cxx_api.h>

namespace simulo {

Ort::Session create_pose_session(const Ort::Env &env, const Ort::SessionOptions &opts);

} // namespace simulo
