#include <cstring>

#include <opencv2/calib3d.hpp>
#include <opencv2/core.hpp>
#include <opencv2/core/types.hpp>
#include <opencv2/imgproc.hpp>

#include "ffi.h"

OpenCvMat *create_opencv_mat(int rows, int cols) {
   return new cv::Mat(rows, cols, CV_8UC3);
}

void destroy_opencv_mat(OpenCvMat *mat) {
   delete mat;
}

unsigned char *get_opencv_mat_data(OpenCvMat *mat) {
   return mat->data;
}

bool find_chessboard(
    OpenCvMat *mat, int pattern_width, int pattern_height, FfiMat3 *out_transform
) {
   cv::Mat &frame = *mat;

   static thread_local cv::Mat gray;
   cv::cvtColor(frame, gray, cv::COLOR_RGB2GRAY);

   std::vector<cv::Point2f> corners;
   bool found = cv::findChessboardCornersSB(
       gray, cv::Size(pattern_width, pattern_height), corners, cv::CALIB_CB_EXHAUSTIVE
   );

   if (!found) {
      return false;
   }

   cv::Point2f tl = corners[0];
   cv::Point2f tr = corners[pattern_width - 1];
   cv::Point2f bl = corners[corners.size() - pattern_width];
   cv::Point2f br = corners[corners.size() - 1];

   std::vector<cv::Point2f> src_points = {tl, tr, bl, br};
   float x_offset = 1.f / (pattern_width + 1);
   float y_offset = 1.f / (pattern_height + 1);
   static std::vector<cv::Point2f> dst_points = {
       // clang-format off
       cv::Point2f(       x_offset,        y_offset), // TL
       cv::Point2f(1.0f - x_offset,        y_offset), // TR
       cv::Point2f(       x_offset, 1.0f - y_offset), // BL
       cv::Point2f(1.0f - x_offset, 1.0f - y_offset), // BR
       // clang-format on
   };

   cv::Mat transform = cv::getPerspectiveTransform(src_points, dst_points);
   std::memcpy(out_transform->data, transform.data, sizeof(FfiMat3));
   return true;
}
