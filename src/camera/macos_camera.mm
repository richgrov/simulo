#include <atomic>
#include <cstring>
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

#include "../ffi.h"

@interface SimuloCameraDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
- (instancetype)init:(void *)out;
- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection;
- (bool)hasNewFrame;
- (void)resetNewFrameFlag;
- (void)setFloatMode:(float *)out;
- (void)lockFrame;
- (void)unlockFrame;

@end

@implementation SimuloCameraDelegate {
   void *out;
   bool float_mode;
   std::mutex imageMutex;
   std::atomic<bool> newFrameAvailable;
}

- (instancetype)init:(void *)out_ {
   self = [super init];
   if (self) {
      newFrameAvailable = false;
      out = out_;
      float_mode = false;
   }
   return self;
}

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {

   CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
   CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);

   auto baseAddress = reinterpret_cast<unsigned char *>(CVPixelBufferGetBaseAddress(imageBuffer));
   size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
   size_t width = CVPixelBufferGetWidth(imageBuffer);
   size_t height = CVPixelBufferGetHeight(imageBuffer);

   {
      std::lock_guard<std::mutex> lock(imageMutex);
      if (float_mode) {
         // Convert from HxWxC uchar to CxHxW float
         auto outf = reinterpret_cast<float *>(out);
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
         std::memcpy(out, baseAddress, height * bytesPerRow);
      }
      newFrameAvailable = true;
   }

   CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
}

- (bool)hasNewFrame {
   return newFrameAvailable.load();
}

- (void)resetNewFrameFlag {
   newFrameAvailable.store(false);
}

- (void)setFloatMode:(float *)out_ {
   float_mode = true;
   out = out_;
}

- (void)lockFrame {
   imageMutex.lock();
}

- (void)unlockFrame {
   imageMutex.unlock();
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

AVCaptureDevice *find_camera() {
   AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession
       discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInWideAngleCamera ]
                             mediaType:AVMediaTypeVideo
                              position:AVCaptureDevicePositionUnspecified];
   NSArray *devices = [discoverySession devices];

   if ([devices count] == 0) {
      return nil;
   }

   return [devices objectAtIndex:0];
}

extern "C" {

bool init_camera(Camera *camera, unsigned char *out) {
   AVCaptureSession *captureSession;

   @autoreleasepool {
      if (!ensure_permission()) {
         return false;
      }

      captureSession = [[AVCaptureSession alloc] init];
      [captureSession setSessionPreset:AVCaptureSessionPreset640x480];

      AVCaptureDevice *device = find_camera();
      if (!device) {
         return false;
      }

      NSError *error = nil;
      AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device
                                                                          error:&error];
      if (!input) {
         return false;
      }

      if (![captureSession canAddInput:input]) {
         return false;
      }
      [captureSession addInput:input];

      AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
      [output setAlwaysDiscardsLateVideoFrames:YES];
      [output setVideoSettings:@{
         (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_24RGB),
         (id)kCVPixelBufferWidthKey : @(640),
         (id)kCVPixelBufferHeightKey : @(480),
      }];

      camera->delegate = [[SimuloCameraDelegate alloc] init:out];
      dispatch_queue_t queue = dispatch_queue_create("com.simulo.cameraQueue", NULL);
      [output setSampleBufferDelegate:camera->delegate queue:queue];

      if ([captureSession canAddOutput:output]) {
         [captureSession addOutput:output];
      } else {
         return false;
      }

      [captureSession startRunning];

      camera->session = captureSession;
      return true;
   }
}

void destroy_camera(Camera *camera) {
   [camera->session stopRunning];
   camera->session = nil;
   camera->delegate = nil;
}

void set_camera_float_mode(Camera *camera, float *out) {
   [camera->delegate setFloatMode:out];
}

void lock_camera_frame(Camera *camera) {
   [camera->delegate lockFrame];
}

void unlock_camera_frame(Camera *camera) {
   [camera->delegate unlockFrame];
}

} // extern "C"
