#include "window.h"

#import <AppKit/AppKit.h>
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <objc/objc.h>

#include "gpu/gpu.h"

using namespace vkad;

namespace {

void resize_metal_layer_to_window(NSWindow *window, CAMetalLayer *metal_layer) {
   metal_layer.drawableSize =
       [window.contentView convertSizeToBacking:window.contentView.frame.size];
}

} // namespace

@interface WindowDelegate : NSObject <NSWindowDelegate> {
   BOOL closed_;
}
@end

@implementation WindowDelegate

- (void)windowDidResize:(NSNotification *)notification {
   NSWindow *window = notification.object;
   CAMetalLayer *metal_layer = (CAMetalLayer *)window.contentView.layer;
   resize_metal_layer_to_window(window, metal_layer);
}

- (void)windowWillClose:(NSNotification *)notification {
   closed_ = true;
}

@end

Window::Window(const Gpu &gpu, const char *title) {
   [NSApplication sharedApplication];
   NSRect bounds = NSMakeRect(0, 0, 1280, 720);
   NSWindow *window = [[NSWindow alloc]
       initWithContentRect:bounds
                 styleMask:NSWindowStyleMaskClosable | NSWindowStyleMaskResizable |
                           NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskTitled
                   backing:NSBackingStoreBuffered
                     defer:NO];

   window.delegate = [[WindowDelegate alloc] init];

   [window center];
   window.title = [NSString stringWithUTF8String:title];
   window.isVisible = YES;
   [window makeKeyAndOrderFront:nil];
   window.releasedWhenClosed = NO;

   metal_layer_ = [[CAMetalLayer alloc] init];
   metal_layer_.device = gpu.device();
   metal_layer_.opaque = YES;
   layer_pixel_format_ = metal_layer_.pixelFormat;
   resize_metal_layer_to_window(window, metal_layer_);
   window.contentView.layer = metal_layer_;

   this->ns_window_ = window;
}

Window::~Window() {
   [ns_window_.delegate release];
   [ns_window_ release];
}

bool Window::poll() {
   if (cursor_captured_) {
      NSRect frame = ns_window_.frame;
      CGPoint centerPoint = CGPointMake(
          frame.origin.x + frame.size.width / 2, frame.origin.y + frame.size.height / 2
      );
      CGWarpMouseCursorPosition(centerPoint);
   }

   @autoreleasepool {
      while (true) {
         NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                             untilDate:[NSDate distantPast]
                                                inMode:NSDefaultRunLoopMode
                                               dequeue:YES];

         if (event == nullptr) {
            break;
         }

         [NSApp sendEvent:event];

         if (![ns_window_ isVisible]) {
            return false;
         }
      }
   }
   return true;
}

void Window::set_capture_mouse(bool capture) {
   cursor_captured_ = capture;

   if (capture) {
      [NSCursor hide];
   } else {
      [NSCursor unhide];
   }
}

int Window::width() const {
   return static_cast<int>(ns_window_.frame.size.width);
}

int Window::height() const {
   return static_cast<int>(ns_window_.frame.size.height);
}
