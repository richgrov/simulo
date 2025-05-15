#include "perception/perception.h"

#include <iostream>
#include <opencv2/imgcodecs.hpp>

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
      Perception perception;
      perception.set_running(true);

      while (true) {
         perception.debug_window();
      }
   } catch (const std::exception &e) {
      std::cerr << e.what() << std::endl;
      return 1;
   }
   return 0;
}
