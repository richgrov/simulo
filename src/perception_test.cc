#include "perception/perception.h"

#include <onnxruntime_cxx_api.h>
#include <opencv2/imgcodecs.hpp>

#include <iostream>
#include <thread>

// #include "projector_detector.h"

using namespace simulo;

int main(int argc, char **argv) {
   /*if (true) {
      ProjectorDetector detector;
      cv::Mat image = cv::imread("image1.png");
      detector.detect_projector_bounds(image);
      return 0;
   }*/

   try {
      auto env = std::make_shared<const Ort::Env>();
      Perception perception1(env, 0);
      Perception perception2(env, 1);
      perception1.set_running(true);
      perception2.set_running(true);

      while (true) {
         perception.debug_window();
      }
   } catch (const std::exception &e) {
      std::cerr << e.what() << std::endl;
      return 1;
   }
   return 0;
}
