#pragma once

#if defined(WIN32) || defined(_WIN32) || defined(__WIN32) && !defined(__CYGWIN__)
#define VKAD_WINDOWS
#elif defined(__APPLE__)
#define VKAD_APPLE
#elif defined(__linux__)
#define VKAD_LINUX
#endif
