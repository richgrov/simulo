cmake_minimum_required (VERSION 3.10)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project("vkad" LANGUAGES C CXX OBJC OBJCXX)

if (CMAKE_PROJECT_NAME STREQUAL PROJECT_NAME)
  include(CTest)
endif()

add_subdirectory(src/vendor/libdeflate)
add_subdirectory(src)
