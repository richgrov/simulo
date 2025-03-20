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

@class WindowDelegate;
@class WindowView;

@interface WindowDelegate : NSObject <NSWindowDelegate, NSApplicationDelegate> {
@public
   Bitfield<256> pressed_keys_;
@public
   Bitfield<256> prev_pressed_keys_;
}
@end

@implementation WindowDelegate

- (void)windowDidResize:(NSNotification *)notification {
   NSWindow *window = notification.object;
   CAMetalLayer *metal_layer = (CAMetalLayer *)window.contentView.layer;
   resize_metal_layer_to_window(window, metal_layer);
}

@end

@interface WindowView : NSView <NSTextInputClient> {
   WindowDelegate *delegate_;
}
@end

@implementation WindowView

- (id)initWithWindowAndDelegate:(vkad::Window *)window delegate:(WindowDelegate *)delegate {
   self = [super init];
   if (self) {
      windowRef_ = window;
      delegate_ = delegate;
      self.wantsLayer = YES;
   }
   return self;
}

- (BOOL)acceptsFirstResponder {
   return YES;
}

- (BOOL)canBecomeKeyView {
   return YES;
}

- (BOOL)wantsUpdateLayer {
   return YES;
}

- (void)keyDown:(NSEvent *)event {
   delegate_->pressed_keys_.set(event.keyCode);
   [self interpretKeyEvents:@[ event ]];
}

- (void)keyUp:(NSEvent *)event {
   delegate_->pressed_keys_.unset(event.keyCode);
}
- (void)setMarkedText:(id)string
        selectedRange:(NSRange)selectedRange
     replacementRange:(NSRange)replacementRange {
}

- (void)unmarkText {
}

- (NSRange)selectedRange {
   return NSMakeRange(NSNotFound, 0);
}

- (NSRange)markedRange {
   return NSMakeRange(NSNotFound, 0);
}

- (BOOL)hasMarkedText {
   return NO;
}

- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range
                                                actualRange:(NSRangePointer)actualRange {
   return nil;
}

- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText {
   return @[];
}

- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
   return NSMakeRect(0, 0, 0, 0);
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point {
   return 0;
}

@end
Window::Window(const Gpu &gpu, const char *title) {
   [NSApplication sharedApplication];
   [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

   NSRect bounds = NSMakeRect(0, 0, 1280, 720);
   NSWindow *window = [[NSWindow alloc]
       initWithContentRect:bounds
                 styleMask:NSWindowStyleMaskClosable | NSWindowStyleMaskResizable |
                           NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskTitled
                   backing:NSBackingStoreBuffered
                     defer:NO];

   window_delegate_ = [[WindowDelegate alloc] init];
   window.delegate = window_delegate_;
   [NSApp setDelegate:window_delegate_];

   window_view_ = [[WindowView alloc] initWithWindowAndDelegate:this delegate:window_delegate_];
   [window setContentView:window_view_];

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

   [NSApp activateIgnoringOtherApps:YES];
}

Window::~Window() {
   [window_delegate_ release];
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

   window_delegate_->prev_pressed_keys_ = window_delegate_->pressed_keys_;

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
      }
   }

   return [ns_window_ isVisible];
}

void Window::set_capture_mouse(bool capture) {
   cursor_captured_ = capture;

   if (capture) {
      [NSCursor hide];
   } else {
      [NSCursor unhide];
   }
}

void Window::request_close() {
   if (!closing_) {
      [ns_window_ performClose:nil];
      closing_ = true;
   }
}

int Window::width() const {
   return static_cast<int>(ns_window_.frame.size.width);
}

int Window::height() const {
   return static_cast<int>(ns_window_.frame.size.height);
}

bool Window::is_key_down(uint8_t key_code) const {
   return window_delegate_->pressed_keys_[key_code];
}

bool Window::key_just_pressed(uint8_t key_code) const {
   return !window_delegate_->prev_pressed_keys_[key_code] &&
          window_delegate_->pressed_keys_[key_code];
}
