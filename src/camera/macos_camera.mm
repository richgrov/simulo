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
- (instancetype)init;
- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection;
- (const unsigned char *)latestImageBytes;
- (bool)hasNewFrame;
- (void)resetNewFrameFlag;
@end

@implementation SimuloCameraDelegate {
   std::vector<unsigned char> imageData;
   std::mutex imageMutex;
   std::atomic<bool> newFrameAvailable;
}

- (instancetype)init {
   self = [super init];
   if (self) {
      newFrameAvailable = false;
   }
   imageData.resize(480 * 640 * 3);
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
      std::memcpy(imageData.data(), baseAddress, height * bytesPerRow);
      newFrameAvailable = true;
   }

   CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
}

- (const unsigned char *)latestImageBytes {
   std::lock_guard<std::mutex> lock(imageMutex);
   return imageData.data();
}

- (bool)hasNewFrame {
   return newFrameAvailable.load();
}

- (void)resetNewFrameFlag {
   newFrameAvailable.store(false);
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

bool init_camera(Camera *camera) {
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

      camera->delegate = [[SimuloCameraDelegate alloc] init];
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

const unsigned char *get_camera_frame(Camera *camera) {
   return [camera->delegate latestImageBytes];
}

} // extern "C"
