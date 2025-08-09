#include "mjpg.h"

#include <stdbool.h>
#include <cstring>
#include <iostream>

#include <opencv2/opencv.hpp>

bool to_rgbu8(unsigned char *mjpg_data, unsigned char *rgb_data, int width, int height) {
    try {
        static thread_local cv::Mat output(height, width, CV_8UC3, rgb_data);
        cv::imdecode(cv::Mat(height, width, CV_8UC1, mjpg_data), cv::IMREAD_COLOR, &output);
        return true;
    } catch (const cv::Exception& e) {
        std::cerr << "OpenCV error in to_rgbu8: " << e.what() << std::endl;
        return false;
    } catch (const std::exception& e) {
        std::cerr << "Standard error in to_rgbu8: " << e.what() << std::endl;
        return false;
    } catch (...) {
        std::cerr << "Unknown error in to_rgbu8" << std::endl;
        return false;
    }
}

bool to_rgbf32(unsigned char *mjpg_data, float *rgb_data) {
    try {
        static thread_local cv::Mat jpg;
        cv::imdecode(cv::Mat(480, 640, CV_8UC1, mjpg_data), cv::IMREAD_COLOR, &jpg);
        static thread_local cv::Mat float_mat(480, 640, CV_32FC3);
        cv::cvtColor(jpg, float_mat, CV_32FC3);

        static thread_local cv::Mat channel;
        for (int c = 2; c >= 0; c--) {
            cv::extractChannel(float_mat, channel, c);
            float* channel_buffer = rgb_data + c * 640 * 640 + (640 - 480) / 2 * 640;
            std::memcpy(channel_buffer, channel.data, 480 * 640 * sizeof(float));
        }
        return true;
    } catch (const cv::Exception& e) {
        std::cerr << "OpenCV error in to_rgbf32: " << e.what() << std::endl;
        return false;
    } catch (const std::exception& e) {
        std::cerr << "Standard error in to_rgbf32: " << e.what() << std::endl;
        return false;
    } catch (...) {
        std::cerr << "Unknown error in to_rgbf32" << std::endl;
        return false;
    }
}