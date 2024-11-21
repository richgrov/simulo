if (CMAKE_SYSTEM_NAME STREQUAL "Linux")
    find_package(X11 REQUIRED)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(WAYLAND REQUIRED wayland-client wayland-protocols)
    pkg_check_modules(XKBCOMMON REQUIRED xkbcommon)
endif()

if (WIN32)
    set(OS_SPECIFIC_FILES
        "window/win32/keys.h"
        "window/win32/window.cc"
        "window/win32/window.h"
    )
elseif (CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(OS_SPECIFIC_FILES
        "window/linux/keys.h"
        "window/linux/window.h"
        "window/linux/window_init.h"
        "window/linux/wl_window.cc"
        "window/linux/wl_window.h"
        "window/linux/x11_window.cc"
        "window/linux/x11_window.h"
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

function(generate_wayland_protocol target xml_path)
    get_filename_component(protocol_name ${xml_path} NAME_WE)
    set(header_output ${CMAKE_CURRENT_LIST_DIR}/window/linux/${protocol_name}-protocol.h)
    set(c_output ${CMAKE_CURRENT_LIST_DIR}/window/linux/${protocol_name}-protocol.c)

    add_custom_command(
        OUTPUT ${header_output}
        COMMAND wayland-scanner client-header ${xml_path} ${header_output}
        DEPENDS ${xml_path}
    )

    add_custom_command(
        OUTPUT ${c_output}
        COMMAND wayland-scanner private-code ${xml_path} ${c_output}
        DEPENDS ${xml_path}
    )

    target_sources(${target} PRIVATE ${header_output} ${c_output})
endfunction()

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
        target_link_libraries(${subject} ${X11_LIBRARIES} libXi.so)

        target_include_directories(${subject} PRIVATE ${WAYLAND_INCLUDE_DIRS})
        target_link_libraries(${subject} ${WAYLAND_LIBRARIES})

        target_include_directories(${subject} PRIVATE ${XKBCOMMON_INCLUDE_DIRS})
        target_link_directories(${subject} PRIVATE ${XKBCOMMON_LIBRARY_DIRS})
        target_link_libraries(${subject} ${XKBCOMMON_LIBRARIES})

        generate_wayland_protocol(${subject} /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml)
        generate_wayland_protocol(${subject} /usr/share/wayland-protocols/unstable/relative-pointer/relative-pointer-unstable-v1.xml)
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
