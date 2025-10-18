#pragma once

#include "util/os_detect.h"

#ifdef VKAD_WINDOWS
#include "win32/window.h" // IWYU pragma: export
#elif defined(VKAD_APPLE)
#include "macos/window.h" // IWYU pragma: export
#elif defined(VKAD_LINUX)

#ifdef SIMULO_KIOSK
#include "linux/drm_window.h"
#else
#include "linux/window_init.h" // IWYU pragma: export
#endif

#else
#error "platform not supported"
#endif
