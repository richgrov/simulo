add_subdirectory(godot-cpp)

if (WIN32)
   set(GODOT_PLATFORM "windows")
elseif (CMAKE_SYSTEM_NAME STREQUAL "Darwin")
   set(GODOT_PLATFORM "macos")
   set(GODOT_PREFIX "lib")
elseif (CMAKE_SYSTEM_NAME STREQUAL "Linux")
   set(GODOT_PLATFORM "linux")
else()
   message(FATAL_ERROR "Unknown platform: ${CMAKE_SYSTEM_NAME}")
endif()

if(CMAKE_BUILD_TYPE MATCHES Debug)
   set(GODOT_CONFIG "template_debug")
elseif(CMAKE_BUILD_TYPE MATCHES Release)
   set(GODOT_CONFIG "template_release")
else()
   message(FATAL_ERROR "Unknown build type: ${CMAKE_BUILD_TYPE}")
endif()

if (NOT CMAKE_SYSTEM_NAME STREQUAL "Darwin")
   if (CMAKE_SIZEOF_VOID_P GREATER 4)
      set(GODOT_ARCH ".x86_64")
   else()
      set(GODOT_ARCH ".x86_32")
   endif()
endif()

set(FULL_LIB_NAME "${GODOT_PREFIX}gdperception.${GODOT_PLATFORM}.${GODOT_CONFIG}${GODOT_ARCH}")

add_library(${FULL_LIB_NAME} SHARED
   "register_types.cc"
)

target_link_libraries(${FULL_LIB_NAME} simulo_common)
target_link_libraries(${FULL_LIB_NAME} godot-cpp)
target_compile_features(${FULL_LIB_NAME} PUBLIC cxx_std_20)

set_target_properties(${FULL_LIB_NAME} PROPERTIES
    FRAMEWORK TRUE
    MACOSX_FRAMEWORK_IDENTIFIER "com.simulo.${BASE_LIB_NAME}"
    OUTPUT_NAME "${FULL_LIB_NAME}"
)

install(
   TARGETS ${FULL_LIB_NAME}
   LIBRARY DESTINATION bin
   FRAMEWORK DESTINATION bin
   RUNTIME DESTINATION bin
)

install(
   FILES gdperception.gdextension
   DESTINATION bin
)
