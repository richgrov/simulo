#include "image.h"

#include <iostream>
#include <span>

#include <Metal/Metal.h>
#include <objc/NSObjCRuntime.h>

#include "gpu/metal/gpu.h"

using namespace simulo;

// Image::Image(const Gpu &gpu, std::span<const uint8_t> data, int width, int height) {
//    MTLTextureDescriptor *texture_desc = [[MTLTextureDescriptor alloc] init];
//    texture_desc.pixelFormat = MTLPixelFormatRGBA8Unorm;
//    texture_desc.width = width;
//    texture_desc.height = height;

//    texture_ = [gpu.device() newTextureWithDescriptor:texture_desc];
//    [texture_desc release];

//    if (texture_ == nullptr) {
//       throw std::runtime_error("Failed to create texture");
//    }

//    [texture_ replaceRegion:MTLRegionMake3D(0, 0, 0, width, height, 1)
//                mipmapLevel:0
//                  withBytes:data.data()
//                bytesPerRow:width * 4];
// }

// Image::~Image() {
//    [texture_ release];
// }
