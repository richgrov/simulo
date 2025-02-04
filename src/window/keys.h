#pragma once

#if defined(WIN32) || defined(_WIN32) || defined(__WIN32) && !defined(__CYGWIN__)
#include "win32/keys.h" // IWYU pragma: export
#elif defined(__linux__)
#include "linux/keys.h" // IWYU pragma: export
#else
#error "platform not supported"
#endif
