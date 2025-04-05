cmake_minimum_required (VERSION 3.10)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project("vkad" LANGUAGES C CXX OBJC OBJCXX)

if (CMAKE_PROJECT_NAME STREQUAL PROJECT_NAME)
  include(CTest)
endif()

set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -DSIMULO_DEBUG")

add_subdirectory(src/vendor/libdeflate)
add_subdirectory(perception_sdk)
add_subdirectory(src)
