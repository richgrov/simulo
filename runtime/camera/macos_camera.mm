#include <array>
#include <atomic>
#include <iostream>
#include <cstring>
#include <cstdlib>
#include <mutex>
#include <vector>

#include <CoreFoundation/CFBase.h>
#include <CoreVideo/CVPixelBuffer.h>

#import <AVFoundation/AVFoundation.h>
#import <Cocoa/Cocoa.h>
#import <CoreImage/CoreImage.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>

#include "macos_camera.h"

@interface SimuloCameraDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
- (instancetype)init:(std::array<void *, 2>)buffers_;
- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection;
- (void)setFloatMode:(std::array<void *, 2>)buffers_;
- (int)swapBuffers;

@end

@implementation SimuloCameraDelegate {
   std::array<void *, 2> buffers;
   std::atomic_bool float_mode;
   std::atomic_bool buffer_written;
   std::atomic_int buffer;
}

- (instancetype)init:(std::array<void *, 2>)buffers_ {
   self = [super init];
   if (self) {
      buffers = buffers_;
   }
   return self;
}

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {

   if (buffer_written) {
      return;
   }

   CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
   CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);

   auto baseAddress = reinterpret_cast<unsigned char *>(CVPixelBufferGetBaseAddress(imageBuffer));
   size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
   size_t width = CVPixelBufferGetWidth(imageBuffer);
   size_t height = CVPixelBufferGetHeight(imageBuffer);

   int buf_idx = buffer % 2;

   if (float_mode) {
      // Convert from HxWxC uchar to CxHxW float
      auto outf = reinterpret_cast<float *>(buffers[buf_idx]);
      size_t channel_size = height * width;
      for (int y = 0; y < height; ++y) {
         for (int x = 0; x < width; ++x) {
            unsigned char *pixel = &baseAddress[y * width * 3 + x * 3];
            size_t ch_stride = 640 * 640;
            int new_y = (640 - 480) / 2 + y;
            outf[ch_stride * 0 + new_y * width + x] = pixel[0];
            outf[ch_stride * 1 + new_y * width + x] = pixel[1];
            outf[ch_stride * 2 + new_y * width + x] = pixel[2];
         }
      }
   } else {
      std::memcpy(buffers[buf_idx], baseAddress, height * bytesPerRow);
   }

   buffer_written = true;
   buffer_written.notify_one();

   CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
}

- (void)setFloatMode:(std::array<void *, 2>)buffers_ {
   float_mode = true;
   buffers = buffers_;
}

- (int)swapBuffers {
   buffer_written.wait(false);
   int ready_buf = buffer % 2;
   buffer++;
   buffer_written = false;
   return ready_buf;
}

@end

bool ensure_permission() {
   AVAuthorizationStatus authStatus =
       [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];

   if (authStatus == AVAuthorizationStatusNotDetermined) {
      dispatch_semaphore_t sema = dispatch_semaphore_create(0);

      [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                               completionHandler:^(BOOL granted) {
                                 dispatch_semaphore_signal(sema);
                               }];

      dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

      authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
   }

   return authStatus == AVAuthorizationStatusAuthorized;
}

AVCaptureDevice *find_device(const char *device_id, size_t device_id_len) {
   NSString *device_id_ns = [[NSString alloc] initWithBytes:device_id length:device_id_len encoding:NSUTF8StringEncoding];
   
   AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession
          discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeExternalUnknown ]
                                mediaType:AVMediaTypeVideo
                                 position:AVCaptureDevicePositionUnspecified];

   NSArray *devices = [discoverySession devices];
   for (AVCaptureDevice *candidate in devices) {
      if ([candidate.localizedName isEqualToString:device_id_ns] || [candidate.uniqueID isEqualToString:device_id_ns]) {
         [candidate retain];
         return candidate;
      }
   }

   return nil;
}

extern "C" {

CameraError init_camera(Camera *camera, unsigned char *buf_a, unsigned char *buf_b, const char *device_id, size_t device_id_len) {
   AVCaptureSession *captureSession;

   @autoreleasepool {
      if (!ensure_permission()) {
         return ErrorNoPermission;
      }

      captureSession = [[AVCaptureSession alloc] init];
      [captureSession setSessionPreset:AVCaptureSessionPreset640x480];

      AVCaptureDevice *device = find_device(device_id, device_id_len);
      if (device == nil) {
         return ErrorNoCamera;
      }

      NSError *error = nil;
      AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device
                                                                          error:&error];

      [device release];

      if (!input) {
         std::cerr << "error: " << error.localizedDescription.UTF8String << std::endl;
         return ErrorCannotCreateCapture;
      }

      if (![captureSession canAddInput:input]) {
         return ErrorCannotAddInput;
      }
      [captureSession addInput:input];

      AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
      [output setAlwaysDiscardsLateVideoFrames:YES];
      [output setVideoSettings:@{
         (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_24RGB),
         (id)kCVPixelBufferWidthKey : @(640),
         (id)kCVPixelBufferHeightKey : @(480),
      }];

      camera->delegate = [[SimuloCameraDelegate alloc] init:std::array<void *, 2>{buf_a, buf_b}];
      dispatch_queue_t queue = dispatch_queue_create("com.simulo.cameraQueue", NULL);
      [output setSampleBufferDelegate:camera->delegate queue:queue];

      if ([captureSession canAddOutput:output]) {
         [captureSession addOutput:output];
      } else {
         return ErrorCannotAddOutput;
      }

      [captureSession startRunning];

      camera->session = captureSession;
      return ErrorNone;
   }
}

void destroy_camera(Camera *camera) {
   [camera->session stopRunning];
   camera->session = nil;
   camera->delegate = nil;
}

void set_camera_float_mode(Camera *camera, float *buf_a, float *buf_b) {
   [camera->delegate setFloatMode:std::array<void *, 2>{buf_a, buf_b}];
}

int swap_camera_buffers(Camera *camera) {
   return [camera->delegate swapBuffers];
}

} // extern "C"
