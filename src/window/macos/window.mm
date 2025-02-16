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
   BOOL _closed;
}
@end

@implementation WindowDelegate

- (void)windowDidResize:(NSNotification *)notification {
   NSWindow *window = notification.object;
   CAMetalLayer *metal_layer = (CAMetalLayer *)window.contentView.layer;
   resize_metal_layer_to_window(window, metal_layer);
}

- (void)windowWillClose:(NSNotification *)notification {
   _closed = true;
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

   CAMetalLayer *metal_layer = [[CAMetalLayer alloc] init];
   metal_layer.device = reinterpret_cast<id<MTLDevice>>(gpu.device());
   metal_layer.opaque = YES;
   resize_metal_layer_to_window(window, metal_layer);
   window.contentView.layer = metal_layer;

   this->ns_window_ = window;
}

Window::~Window() {
   NSWindow *window = reinterpret_cast<NSWindow *>(ns_window_);
   [window release];
}

bool Window::poll() {
   auto window = reinterpret_cast<NSWindow *>(ns_window_);

   @autoreleasepool {
      while (true) {
         NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                             untilDate:[NSDate distantFuture]
                                                inMode:NSDefaultRunLoopMode
                                               dequeue:YES];

         if (event == nullptr) {
            break;
         }

         [NSApp sendEvent:event];

         if (![window isVisible]) {
            return false;
         }
      }
   }
   return true;
}
