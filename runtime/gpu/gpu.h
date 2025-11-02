#pragma once

#include "util/os_detect.h"

#if defined(VKAD_WINDOWS) || defined(VKAD_LINUX)
#include "vulkan/gpu.h" // IWYU pragma: export
#elif defined(VKAD_APPLE)
#include "vulkan/gpu.h" // IWYU pragma: export
#else
#error "platform not supported"
#endif
