if (WIN32)
    set(OS_SPECIFIC_FILES
        "window/win32/window.cc"
        "window/win32/window.h"
    )
endif()

add_executable(villa 
   "gpu/gpu.cc"
   "gpu/gpu.h"
   "gpu/shader.cc"
   "gpu/shader.h"
   "gpu/swapchain.cc"
   "gpu/swapchain.h"
   "util/array.h"
   "window/window.h"
   "app.cc"
   "app.h"
   "main.cc"
   ${OS_SPECIFIC_FILES}
)

target_include_directories(villa PRIVATE "${PROJECT_SOURCE_DIR}/src")

target_link_directories(villa PRIVATE "$ENV{VULKAN_SDK}/Lib")
target_link_libraries(villa "vulkan-1.lib")
target_include_directories(villa PRIVATE "$ENV{VULKAN_SDK}/Include")

set_property(TARGET villa PROPERTY CXX_STANDARD 20)

set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -DVILLA_DEBUG")
