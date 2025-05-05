#include "window.h"

#import <AppKit/AppKit.h>
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <objc/objc.h>

#include "gpu/gpu.h"
#include "window/macos/keys.h"

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
@public
   Bitfield<256> pressed_keys_;
@public
   Bitfield<256> prev_pressed_keys_;
   int mouse_x_;
   int mouse_y_;
   int delta_mouse_x_;
   int delta_mouse_y_;
   bool mouse_down_;
   char typed_chars_[64];
   int next_typed_letter_;
}
@end

@implementation WindowView

- (id)initWithDelegate:(WindowDelegate *)delegate {
   self = [super init];
   if (self) {
      self.wantsLayer = YES;
   }
   return self;
}

- (void)update {
   prev_pressed_keys_ = pressed_keys_;

   std::memset(typed_chars_, 0, sizeof(typed_chars_));
   next_typed_letter_ = 0;

   delta_mouse_x_ = 0;
   delta_mouse_y_ = 0;
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

- (void)mouseDown:(NSEvent *)event {
   mouse_down_ = true;
}

- (void)mouseUp:(NSEvent *)event {
   mouse_down_ = false;
}

- (void)mouseMoved:(NSEvent *)event {
   NSPoint locationInWindow = [event locationInWindow];
   NSPoint locationInView = [self convertPoint:locationInWindow fromView:nil];

   delta_mouse_x_ = event.deltaX;
   delta_mouse_y_ = -event.deltaY;
   mouse_x_ = static_cast<int>(locationInView.x);
   mouse_y_ = static_cast<int>(self.frame.size.height - locationInView.y);
}

- (void)mouseDragged:(NSEvent *)event {
   [self mouseMoved:event];
}

- (void)keyDown:(NSEvent *)event {
   pressed_keys_.set(event.keyCode);

   if (next_typed_letter_ < sizeof(typed_chars_)) {
      switch (event.keyCode) {
      case VKAD_KEY_DELETE:
         typed_chars_[next_typed_letter_++] = '\b';
         return;
      case VKAD_KEY_RETURN:
         typed_chars_[next_typed_letter_++] = '\r';
         return;
      }
   }

   [self interpretKeyEvents:@[ event ]];
}

- (void)keyUp:(NSEvent *)event {
   pressed_keys_.unset(event.keyCode);
}

- (void)scrollWheel:(NSEvent *)event {
}

#pragma mark - NSTextInputClient Protocol

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
   if ([string isKindOfClass:[NSString class]]) {
      NSString *nsString = (NSString *)string;
      const char *utf8Chars = [nsString UTF8String];
      size_t len = strlen(utf8Chars);

      if (next_typed_letter_ + len < sizeof(typed_chars_)) {
         memcpy(typed_chars_ + next_typed_letter_, utf8Chars, len);
         next_typed_letter_ += static_cast<int>(len);
      }
   }
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

   window_view_ = [[WindowView alloc] initWithDelegate:window_delegate_];
   [window setContentView:window_view_];

   [window center];
   window.title = [NSString stringWithUTF8String:title];
   window.isVisible = YES;
   window.acceptsMouseMovedEvents = YES;
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

   [window_view_ update];

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
      CGAssociateMouseAndMouseCursorPosition(false);
   } else {
      [NSCursor unhide];
      CGAssociateMouseAndMouseCursorPosition(true);
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

int Window::mouse_x() const {
   return window_view_->mouse_x_;
}

int Window::mouse_y() const {
   return window_view_->mouse_y_;
}

int Window::delta_mouse_x() const {
   return window_view_->delta_mouse_x_;
}

int Window::delta_mouse_y() const {
   return window_view_->delta_mouse_y_;
}

bool Window::left_clicking() const {
   return window_view_->mouse_down_;
}

bool Window::is_key_down(uint8_t key_code) const {
   return window_view_->pressed_keys_[key_code];
}

bool Window::key_just_pressed(uint8_t key_code) const {
   return !window_view_->prev_pressed_keys_[key_code] && window_view_->pressed_keys_[key_code];
}

std::string_view Window::typed_chars() const {
   return std::string_view(window_view_->typed_chars_, window_view_->next_typed_letter_);
}
