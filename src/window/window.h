#pragma once

#if defined(WIN32) || defined(_WIN32) || defined(__WIN32) && !defined(__CYGWIN__)
#include "win32/window.h" // IWYU pragma: export
#elif defined(__linux__)
#include "linux/window_init.h" // IWYU pragma: export
#else
#error "platform not supported"
#endif
