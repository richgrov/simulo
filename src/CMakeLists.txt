if (WIN32)
    set(OS_SPECIFIC_FILES
        "window/win32/window.cc"
        "window/win32/window.h"
    )
endif()

add_library(villa 
   "gpu/command_pool.cc"
   "gpu/command_pool.h"
   "gpu/descriptor_pool.cc"
   "gpu/descriptor_pool.h"
   "gpu/instance.cc"
   "gpu/instance.h"
   "gpu/pipeline.cc"
   "gpu/pipeline.h"
   "gpu/physical_device.cc"
   "gpu/physical_device.h"
   "gpu/shader.cc"
   "gpu/shader.h"
   "gpu/swapchain.cc"
   "gpu/swapchain.h"
   "gpu/buffer.cc"
   "gpu/buffer.h"
   "math/vec2.h"
   "math/vec3.h"
   "util/array.h"
   "util/rand.h"
   "window/window.h"
   "game.cc"
   "game.h"
   ${OS_SPECIFIC_FILES}
)

target_include_directories(villa PUBLIC "${PROJECT_SOURCE_DIR}/src")

target_link_directories(villa PUBLIC "$ENV{VULKAN_SDK}/Lib")
target_link_libraries(villa "vulkan-1.lib")
target_include_directories(villa PUBLIC "$ENV{VULKAN_SDK}/Include")

set_property(TARGET villa PROPERTY CXX_STANDARD 20)

set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -DVILLA_DEBUG")
