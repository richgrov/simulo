#ifndef VKAD_UTIL_ASSERT_H_
#define VKAD_UTIL_ASSERT_H_

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

#endif // !VKAD_UTIL_ASSERT_H_
