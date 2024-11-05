#ifndef VKAD_WINDOW_WINDOW_H_
#define VKAD_WINDOW_WINDOW_H_

#if defined(WIN32) || defined(_WIN32) || defined(__WIN32) && !defined(__CYGWIN__)
#include "win32/window.h"
#elif defined(__linux__)
#include "linux/x11_window.h"
#else
#error "platform not supported"
#endif

#endif // !VKAD_WINDOW_WINDOW_H_
