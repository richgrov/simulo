#include "mjpg.h"

#include <stdbool.h>
#include <cstring>

#include <opencv2/opencv.hpp>

bool to_rgbu8(const unsigned char *mjpg_data, unsigned char *rgb_data, int width, int height) {
    cv::Mat mjpg_mat(height, width, CV_8UC1, mjpg_data);
    cv::Mat rgb_mat(height, width, CV_8UC3, rgb_data);
    cv::cvtColor(mjpg_mat, rgb_mat, cv::COLOR_YUV2RGB_YUYV);
    return true;
}

bool to_rgbf32(const unsigned char *mjpg_data, float *rgb_data) {
    cv::Mat mjpg_mat(480, 640, CV_8UC1, mjpg_data);
    static cv::Mat rgb_mat(480, 640, CV_32FC3);
    cv::cvtColor(mjpg_mat, rgb_mat, cv::COLOR_YUV2RGB_YUYV);

    static cv::Mat channel;
    for (int c = 0; c < 3; c++) {
        cv::extractChannel(rgb_mat, channel, c);
        float* channel_buffer = rgb_data + c * 640 * 640;
        std::memcpy(channel_buffer, channel.data, 480 * 640 * sizeof(float));
    }
    
    return true;
}