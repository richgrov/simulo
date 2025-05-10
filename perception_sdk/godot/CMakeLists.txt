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

set(FULL_LIB_NAME "${GODOT_PREFIX}gdperception.${GODOT_PLATFORM}.${GODOT_CONFIG}")

add_library(${FULL_LIB_NAME} SHARED
   "register_types.cc"
)

target_link_libraries(${FULL_LIB_NAME} perception_sdk)
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
