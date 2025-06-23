#pragma once

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

namespace simulo {

class Gpu {
public:
   Gpu();
   ~Gpu();

#ifdef __OBJC__
   id<MTLDevice> device() const {
      return mt_device_;
   }

   id<MTLLibrary> library() const {
      return library_;
   }
#endif

private:
#ifdef __OBJC__
   id<MTLDevice> mt_device_;
   id<MTLLibrary> library_;
#else
   void *mt_device_;
   void *library_;
#endif
};

} // namespace simulo
