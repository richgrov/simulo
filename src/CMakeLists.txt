if (WIN32)
    set(OS_SPECIFIC_FILES
        "window/win32/window.cc"
        "window/win32/window.h"
    )

    set(VULKAN true)
endif()

if (VULKAN)
   add_compile_definitions(VILLA_VULKAN)
   set(GPU_SPECIFIC_FILES
      "gpu/vk/gpu.cc"
      "gpu/vk/gpu.h"
   )
endif()

add_executable(villa 
   "gpu/gpu.h"
   "window/window.h"
   "app.cc"
   "app.h"
   "main.cc"
   ${OS_SPECIFIC_FILES}
   ${GPU_SPECIFIC_FILES}
)

if (VULKAN)
   target_link_directories(villa PRIVATE "$ENV{VULKAN_SDK}/Lib")
   target_link_libraries(villa "vulkan-1.lib")
   target_include_directories(villa PRIVATE "$ENV{VULKAN_SDK}/Include")
endif()

set_property(TARGET villa PROPERTY CXX_STANDARD 20)

set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -DVILLA_DEBUG")
