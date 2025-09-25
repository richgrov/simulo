#include "opencv.h"

#include <cstring>
#include <opencv2/calib3d.hpp>
#include <opencv2/core.hpp>
#include <opencv2/core/types.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <vector>

CvStatus mat_init(CvMat *mat, int rows, int cols, CvMatType type) {
   static_assert(sizeof(cv::Mat) == sizeof(CvMat));
   static_assert(alignof(cv::Mat) == alignof(CvMat));

   try {
      new (mat) cv::Mat(rows, cols, type);
   } catch (const cv::Exception &e) {
      return static_cast<CvStatus>(e.code);
   } catch (const std::exception &e) {
      return StatStdException;
   } catch (...) {
      return StatUnknownException;
   }
   return StatOk;
}

CvStatus mat_convert(CvMat *out, const CvMat *in, CvConvert convert) {
   try {
      auto *in_mat = reinterpret_cast<const cv::Mat *>(in);
      cv::Mat *out_mat = reinterpret_cast<cv::Mat *>(out);
      cv::cvtColor(*in_mat, *out_mat, static_cast<int>(convert));
   } catch (const cv::Exception &e) {
      return static_cast<CvStatus>(e.code);
   } catch (const std::exception &e) {
      return StatStdException;
   } catch (...) {
      return StatUnknownException;
   }
   return StatOk;
}

CvStatus mat_release(CvMat *mat) {
   try {
      cv::Mat *m = reinterpret_cast<cv::Mat *>(mat);
      m->release();
   } catch (const cv::Exception &e) {
      return static_cast<CvStatus>(e.code);
   } catch (const std::exception &e) {
      return StatStdException;
   } catch (...) {
      return StatUnknownException;
   }
   return StatOk;
}

CvStatus mat_wrap(CvMat *out, void *data, int rows, int cols, CvMatType type) {
   try {
      new (out) cv::Mat(rows, cols, type, data);
   } catch (const cv::Exception &e) {
      return static_cast<CvStatus>(e.code);
   } catch (const std::exception &e) {
      return StatStdException;
   } catch (...) {
      return StatUnknownException;
   }
   return StatOk;
}

CvStatus mat_decode(CvMat *dst, const unsigned char *data, int data_len, CvImreadFlags flags) {
   try {
      auto *dst_mat = reinterpret_cast<cv::Mat *>(dst);
      cv::Mat data_mat(1, data_len, CV_8UC1, const_cast<unsigned char *>(data));
      cv::imdecode(data_mat, flags, dst_mat);
   } catch (const cv::Exception &e) {
      return static_cast<CvStatus>(e.code);
   } catch (const std::exception &e) {
      return StatStdException;
   } catch (...) {
      return StatUnknownException;
   }
   return StatOk;
}

CvStatus mat_flip(CvMat *out, const CvMat *in, int flip_code) {
   try {
      cv::Mat *in_mat = reinterpret_cast<cv::Mat *>(const_cast<CvMat *>(in));
      cv::Mat *out_mat = reinterpret_cast<cv::Mat *>(out);
      cv::flip(*in_mat, *out_mat, flip_code);
   } catch (const cv::Exception &e) {
      return static_cast<CvStatus>(e.code);
   } catch (const std::exception &e) {
      return StatStdException;
   } catch (...) {
      return StatUnknownException;
   }
   return StatOk;
}

CvStatus mat_convert_to(CvMat *out, const CvMat *in, CvMatType type, double alpha, double beta) {
   try {
      cv::Mat *in_mat = reinterpret_cast<cv::Mat *>(const_cast<CvMat *>(in));
      cv::Mat *out_mat = reinterpret_cast<cv::Mat *>(out);
      in_mat->convertTo(*out_mat, static_cast<int>(type), alpha, beta);
   } catch (const cv::Exception &e) {
      return static_cast<CvStatus>(e.code);
   } catch (const std::exception &e) {
      return StatStdException;
   } catch (...) {
      return StatUnknownException;
   }
   return StatOk;
}

CvStatus mat_extract_channel(CvMat *out, const CvMat *in, int channel_index) {
   try {
      cv::Mat *in_mat = reinterpret_cast<cv::Mat *>(const_cast<CvMat *>(in));
      cv::Mat *out_mat = reinterpret_cast<cv::Mat *>(out);
      cv::extractChannel(*in_mat, *out_mat, channel_index);
   } catch (const cv::Exception &e) {
      return static_cast<CvStatus>(e.code);
   } catch (const std::exception &e) {
      return StatStdException;
   } catch (...) {
      return StatUnknownException;
   }
   return StatOk;
}

int mat_is_empty(const CvMat *m) {
   const cv::Mat *mat = reinterpret_cast<const cv::Mat *>(m);
   return mat->empty() ? 1 : 0;
}

int mat_rows(const CvMat *m) {
   const cv::Mat *mat = reinterpret_cast<const cv::Mat *>(m);
   return mat->rows;
}

int mat_cols(const CvMat *m) {
   const cv::Mat *mat = reinterpret_cast<const cv::Mat *>(m);
   return mat->cols;
}

int mat_channels(const CvMat *m) {
   const cv::Mat *mat = reinterpret_cast<const cv::Mat *>(m);
   return mat->channels();
}

unsigned long long mat_total(const CvMat *m) {
   const cv::Mat *mat = reinterpret_cast<const cv::Mat *>(m);
   return static_cast<unsigned long long>(mat->total());
}

unsigned char *mat_data(CvMat *m) {
   cv::Mat *mat = reinterpret_cast<cv::Mat *>(m);
   return mat->data;
}

CvStatus find_chessboard_transform(
    const CvMat *rgb, int pattern_width, int pattern_height, CvCalibChessboardFlags flags,
    double *out3x3, bool *out_found
) {
   try {
      const cv::Mat *frame = reinterpret_cast<const cv::Mat *>(rgb);

      std::vector<cv::Point2f> corners;
      bool found = cv::findChessboardCornersSB(
          *frame, cv::Size(pattern_width, pattern_height), corners, flags
      );

      *out_found = found;
      if (!found) {
         return StatOk;
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
      std::memcpy(out3x3, transform.data, 9 * sizeof(double));
   } catch (const cv::Exception &e) {
      return static_cast<CvStatus>(e.code);
   } catch (const std::exception &e) {
      return StatStdException;
   } catch (...) {
      return StatUnknownException;
   }
   return StatOk;
}