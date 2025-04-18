find_package(OpenCV REQUIRED)

add_library(perception_sdk
   "perception.cc"
   "perception.h"
   "pose_model.cc"
   "pose_model.h"
)

target_include_directories(perception_sdk 
   PUBLIC 
      ${OpenCV_INCLUDE_DIRS}
   PRIVATE
      ${CMAKE_CURRENT_SOURCE_DIR}
)
target_link_libraries(perception_sdk PUBLIC ${OpenCV_LIBS})

function(embed_binary target file)
   add_custom_command(
      OUTPUT ${file}.h
      COMMAND xxd -i ${file} ${file}.h
      DEPENDS ${file}
      WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
   )

   target_sources(${target} PRIVATE ${file}.h)
endfunction()

target_compile_features(perception_sdk PUBLIC cxx_std_20)

embed_binary(perception_sdk "onnx_exporter/yolo11n-pose.onnx")

if (BUILD_TESTING)
   add_executable(perception_test "test.cc")
   target_link_libraries(perception_test perception_sdk)
endif()

add_subdirectory(godot)
