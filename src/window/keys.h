#ifndef VKAD_WINDOW_KEYS_H_
#define VKAD_WINDOW_KEYS_H_

#if defined(WIN32) || defined(_WIN32) || defined(__WIN32) && !defined(__CYGWIN__)
#include "win32/keys.h"
#elif defined(__linux__)
#include "x11/keys.h"
#else
#error "platform not supported"
#endif

#endif // !VKAD_WINDOW_KEYS_H_
