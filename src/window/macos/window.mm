#include <AppKit/AppKit.h>
#import <Cocoa/Cocoa.h>

#include "window.h"

using namespace vkad;

Window::Window(const char *title) {
   NSRect bounds = NSMakeRect(0, 0, 1280, 720);
   NSWindow *window = [[NSWindow alloc] initWithContentRect:bounds
                                                  styleMask:NSWindowStyleMaskResizable
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];

   [window center];
   [window setTitle:[NSString stringWithUTF8String:title]];

   this->ns_window_ = window;
}

Window::~Window() {
   NSWindow *window = reinterpret_cast<NSWindow *>(ns_window_);
   [window release];
}
