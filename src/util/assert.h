#ifndef VKAD_UTIL_ASSERT_H_
#define VKAD_UTIL_ASSERT_H_

#include <cstdlib>
#include <format>
#include <iostream>

#define VKAD_PANIC(msg, ...)                                                                      \
   std::cerr << std::format(msg, __VA_ARGS__) << "\n";                                             \
   std::abort();

#endif // !VKAD_UTIL_ASSERT_H_
