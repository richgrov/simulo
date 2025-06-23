#pragma once

#include <cstdlib>
#include <format>
#include <iostream>

#define VKAD_PANIC(msg, ...)                                                                       \
   std::cerr << std::format(msg, __VA_ARGS__) << "\n";                                             \
   std::abort();

#define VKAD_ASSERT(cond, msg)                                                                     \
   if (!(cond)) {                                                                                  \
      std::cerr << std::format("{}:{}: {}", __FILE__, __LINE__, msg) << "\n";                      \
      std::abort();                                                                                \
   }

#ifdef VKAD_DEBUG
#define VKAD_DEBUG_ASSERT(cond, msg, ...)                                                          \
   if (!(cond)) {                                                                                  \
      std::cerr << std::format("{}:{}: " msg, __FILE__, __LINE__, __VA_ARGS__) << "\n";            \
      std::abort();                                                                                \
   }

#else
#define VKAD_DEBUG_ASSERT(...)
#endif
