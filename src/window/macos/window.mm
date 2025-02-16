#include <AppKit/AppKit.h>
#import <Cocoa/Cocoa.h>

#include "window.h"

using namespace vkad;

Window::Window(const char *title) {
   [NSApplication sharedApplication];
   NSRect bounds = NSMakeRect(0, 0, 1280, 720);
   NSWindow *window = [[NSWindow alloc]
       initWithContentRect:bounds
                 styleMask:NSWindowStyleMaskClosable | NSWindowStyleMaskResizable |
                           NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskTitled
                   backing:NSBackingStoreBuffered
                     defer:NO];

   [window center];
   [window setTitle:[NSString stringWithUTF8String:title]];
   [window makeKeyAndOrderFront:nil];

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
