#include "mjpg.h"

#include <stdbool.h>
#include <cstring>
#include <iostream>

#include <opencv2/opencv.hpp>

bool to_rgbu8(unsigned char *mjpg_data, unsigned char *rgb_data, int width, int height, int data_size) {
    try {
        cv::Mat jpeg_data(1, data_size, CV_8UC1, mjpg_data);
        cv::Mat output(height, width, CV_8UC3, rgb_data);
        cv::Mat result = cv::imdecode(jpeg_data, cv::IMREAD_COLOR_RGB);
        if (result.empty()) {
            std::cerr << "Failed to decode JPEG data" << std::endl;
            return false;
        }

        if (result.rows != height || result.cols != width) {
            std::cerr << "Decoded image size mismatch: expected " << width << "x" << height 
                      << ", got " << result.cols << "x" << result.rows << std::endl;
            return false;
        }

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

bool to_rgbf32(unsigned char *mjpg_data, float *rgb_data, int data_size) {
    try {
        cv::Mat jpeg_data(1, data_size, CV_8UC1, mjpg_data);
        static thread_local cv::Mat buffer;
        cv::Mat decoded = cv::imdecode(jpeg_data, cv::IMREAD_COLOR_RGB, &buffer);
        
        if (decoded.empty()) {
            std::cerr << "Failed to decode JPEG data in to_rgbf32" << std::endl;
            return false;
        }
        
        if (decoded.rows != 480 || decoded.cols != 640) {
            std::cerr << "Decoded image size mismatch in to_rgbf32: expected 640x480, got " 
                      << decoded.cols << "x" << decoded.rows << std::endl;
            return false;
        }
        
        static thread_local cv::Mat float_mat(480, 640, CV_32FC3);
        decoded.convertTo(float_mat, CV_32FC3);

        static thread_local cv::Mat channel;
        for (int c = 0; c < 3; c++) {
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