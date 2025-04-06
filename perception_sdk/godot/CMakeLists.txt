add_subdirectory(godot-cpp)

# print build type
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")

set(BASE_LIB_NAME "gdperception")

if(CMAKE_BUILD_TYPE MATCHES Debug)
   set(GODOT_SUFFIX "macos.template_debug")
elseif(CMAKE_BUILD_TYPE MATCHES Release)
   set(GODOT_SUFFIX "macos.template_release")
else()
   message(FATAL_ERROR "Unknown build type: ${CMAKE_BUILD_TYPE}")
endif()

set(FULL_LIB_NAME "lib${BASE_LIB_NAME}.${GODOT_SUFFIX}")

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
