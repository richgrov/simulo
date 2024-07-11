#ifndef VILLA_UTIL_ASSERT_H_
#define VILLA_UTIL_ASSERT_H_

#include <cstdlib>
#include <format>
#include <iostream>

#define VILLA_PANIC(msg, ...)                                                                      \
   std::cerr << std::format(msg, __VA_ARGS__) << "\n";                                             \
   std::abort();

#endif // !VILLA_UTIL_ASSERT_H_
