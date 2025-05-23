#include <atomic>
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
- (int)latestImageWidth;
- (int)latestImageHeight;
- (int)latestImageBytesPerRow;
- (bool)hasNewFrame;
- (void)resetNewFrameFlag;
@end

@implementation SimuloCameraDelegate {
   std::vector<unsigned char> imageData;
   std::mutex imageMutex;
   int imageWidth;
   int imageHeight;
   int imageBytesPerRow;
   std::atomic<bool> newFrameAvailable;
}

- (instancetype)init {
   self = [super init];
   if (self) {
      imageWidth = 0;
      imageHeight = 0;
      imageBytesPerRow = 0;
      newFrameAvailable = false;
   }
   return self;
}

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {

   CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
   CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);

   void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
   size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
   size_t width = CVPixelBufferGetWidth(imageBuffer);
   size_t height = CVPixelBufferGetHeight(imageBuffer);

   CIImage *ciImage = [CIImage imageWithCVImageBuffer:imageBuffer];

   CIContext *context = [CIContext contextWithOptions:nil];
   CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

   size_t newBytesPerRow = width * 4;
   size_t dataSize = height * newBytesPerRow;

   std::vector<unsigned char> tempBuffer(dataSize);

   CGImageRef cgImage = [context createCGImage:ciImage fromRect:ciImage.extent];
   CGContextRef cgContext = CGBitmapContextCreate(
       tempBuffer.data(), width, height,
       8, // 8 bits per component
       newBytesPerRow, colorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host
   );

   CGContextDrawImage(cgContext, CGRectMake(0, 0, width, height), cgImage);

   {
      std::lock_guard<std::mutex> lock(imageMutex);
      imageData = std::move(tempBuffer);
      imageWidth = static_cast<int>(width);
      imageHeight = static_cast<int>(height);
      imageBytesPerRow = static_cast<int>(newBytesPerRow);
      newFrameAvailable = true;
   }

   CGContextRelease(cgContext);
   CGImageRelease(cgImage);
   CGColorSpaceRelease(colorSpace);
   CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
}

- (const unsigned char *)latestImageBytes {
   std::lock_guard<std::mutex> lock(imageMutex);
   return imageData.data();
}

- (int)latestImageWidth {
   std::lock_guard<std::mutex> lock(imageMutex);
   return imageWidth;
}

- (int)latestImageHeight {
   std::lock_guard<std::mutex> lock(imageMutex);
   return imageHeight;
}

- (int)latestImageBytesPerRow {
   std::lock_guard<std::mutex> lock(imageMutex);
   return imageBytesPerRow;
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
         (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_128RGBAFloat),
         (id)kCVPixelBufferMetalCompatibilityKey : @(YES)
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
