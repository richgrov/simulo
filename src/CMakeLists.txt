if (CMAKE_SYSTEM_NAME STREQUAL "Linux")
    find_package(X11 REQUIRED)
endif()

if (WIN32)
    set(OS_SPECIFIC_FILES
        "window/win32/keys.h"
        "window/win32/window.cc"
        "window/win32/window.h"
    )
elseif (CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(OS_SPECIFIC_FILES
        "window/x11/window.cc"
        "window/x11/window.h"
    )
endif()

set(SOURCE_FILES
   "entity/player.cc"
   "entity/player.h"
   "geometry/circle.cc"
   "geometry/circle.h"
   "geometry/geometry.h"
   "geometry/model.cc"
   "geometry/model.h"
   "geometry/shape.cc"
   "geometry/shape.h"
   "gpu/command_pool.cc"
   "gpu/command_pool.h"
   "gpu/descriptor_pool.cc"
   "gpu/descriptor_pool.h"
   "gpu/device.cc"
   "gpu/device.h"
   "gpu/image.cc"
   "gpu/image.h"
   "gpu/instance.cc"
   "gpu/instance.h"
   "gpu/pipeline.cc"
   "gpu/pipeline.h"
   "gpu/physical_device.cc"
   "gpu/physical_device.h"
   "gpu/status.h"
   "gpu/swapchain.cc"
   "gpu/swapchain.h"
   "gpu/buffer.cc"
   "gpu/buffer.h"
   "math/angle.h"
   "math/mat4.h"
   "math/vec2.h"
   "math/vec3.h"
   "ui/font.cc"
   "ui/font.h"
   "ui/widget.h"
   "util/assert.h"
   "util/bitfield.h"
   "util/memory.h"
   "util/rand.h"
   "util/slab.h"
   "vendor/stb_image.h"
   "vendor/stb_truetype.h"
   "window/keys.h"
   "window/window.h"
   "app.cc"
   "app.h"
   "renderer.cc"
   "renderer.h"
   "mesh.h"
   "stl.cc"
   "stl.h"
   ${OS_SPECIFIC_FILES}
)

add_executable(vkad ${SOURCE_FILES} "main.cc")

function(setup_targets subject)
    target_include_directories(${subject} PUBLIC "${PROJECT_SOURCE_DIR}/src")

    # Vulkan
    if (WIN32)
        target_link_directories(${subject} PUBLIC "$ENV{VULKAN_SDK}/Lib")
        target_link_libraries(${subject} "vulkan-1.lib")
        target_include_directories(${subject} PUBLIC "$ENV{VULKAN_SDK}/Include")
    elseif (CMAKE_SYSTEM_NAME STREQUAL "Linux")
        target_link_libraries(${subject} libvulkan.so)
    endif()

    if (CMAKE_SYSTEM_NAME STREQUAL "Linux")
        target_include_directories(${subject} PRIVATE ${X11_INCLUDE_DIR})
        target_link_libraries(${subject} ${X11_LIBRARIES})
    endif()

    set_property(TARGET ${subject} PROPERTY CXX_STANDARD 20)
endfunction()

setup_targets(vkad)

set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -DVKAD_DEBUG")

if (BUILD_TESTING)
    add_executable(vkad_test
        "test_main.cc"
        "math/angle_test.cc"
        ${SOURCE_FILES}
    )

    setup_targets(vkad_test)
endif()
