find_package(OpenCV REQUIRED)

add_library(perception_sdk
   "perception.cc"
   "perception.h"
   "pose_model.cc"
   "pose_model.h"
)

if (WIN32)
   target_link_directories(perception_sdk PUBLIC ${ONNXRuntime_DIR}/lib)
   target_link_libraries(perception_sdk PUBLIC onnxruntime)
   target_include_directories(perception_sdk PUBLIC ${ONNXRuntime_DIR}/include)
else()
   find_package(ONNXRuntime REQUIRED)
   target_link_libraries(perception_sdk PUBLIC onnxruntime::onnxruntime)
endif()

target_include_directories(perception_sdk
   PUBLIC
      ${OpenCV_INCLUDE_DIRS}
   PRIVATE
      ${CMAKE_CURRENT_SOURCE_DIR}
)
target_link_libraries(perception_sdk PUBLIC ${OpenCV_LIBS})

function(embed_model target model)
   string(REPLACE "-" "_" file_name ${model})
   add_custom_command(
      OUTPUT ${file_name}.h
      COMMAND bash -c 'curl -sL https://simulo-cdn.tysonjenkins.dev/${model}.onnx | xxd -i -n ${file_name} > ${file_name}.h'
      WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
   )

   target_sources(${target} PRIVATE ${file_name}.h)
endfunction()

target_compile_features(perception_sdk PUBLIC cxx_std_20)

embed_model(perception_sdk yolo11n-pose)

if (BUILD_TESTING)
   add_executable(perception_test "test.cc")
   target_link_libraries(perception_test perception_sdk)
endif()

add_subdirectory(godot)
