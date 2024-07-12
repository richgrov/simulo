if (WIN32)
    set(OS_SPECIFIC_FILES
        "window/win32/keys.h"
        "window/win32/window.cc"
        "window/win32/window.h"
    )
endif()

set(SOURCE_FILES
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
   "gpu/shader.cc"
   "gpu/shader.h"
   "gpu/status.h"
   "gpu/swapchain.cc"
   "gpu/swapchain.h"
   "gpu/buffer.cc"
   "gpu/buffer.h"
   "math/angle.h"
   "math/mat4.h"
   "math/vec2.h"
   "math/vec3.h"
   "util/assert.h"
   "util/memory.h"
   "util/rand.h"
   "vendor/stb_image.h"
   "window/keys.h"
   "window/window.h"
   "game.cc"
   "game.h"
   "sound.cc"
   "sound.h"
   ${OS_SPECIFIC_FILES}
)

add_library(villa ${SOURCE_FILES})

function(setup_targets subject)
    target_include_directories(${subject} PUBLIC "${PROJECT_SOURCE_DIR}/src")

    # Vulkan
    target_link_directories(${subject} PUBLIC "$ENV{VULKAN_SDK}/Lib")
    target_link_libraries(${subject} "vulkan-1.lib")
    target_include_directories(${subject} PUBLIC "$ENV{VULKAN_SDK}/Include")
    
    # FMOD
    target_link_directories(${subject} PUBLIC "$ENV{FMOD_HOME}/lib/x64")
    target_link_libraries(${subject} fmod.dll)
    target_include_directories(${subject} PUBLIC "$ENV{FMOD_HOME}/inc")

    set_property(TARGET ${subject} PROPERTY CXX_STANDARD 20)
endfunction()

setup_targets(villa)

set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -DVILLA_DEBUG")

if (BUILD_TESTING)
    add_executable(villa_test
        "test_main.cc"
        "math/angle_test.cc"
        ${SOURCE_FILES}
    )

    setup_targets(villa_test)
endif()
