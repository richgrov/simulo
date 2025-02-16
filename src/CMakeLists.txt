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
    set(VULKAN TRUE)
elseif (CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(OS_SPECIFIC_FILES
        "window/macos/window.h"
        "window/macos/window.mm"
    )

    set(GPU_FILES
        "gpu/metal/gpu.h"
        "gpu/metal/gpu.mm"
        "render/mt_renderer.h"
    )
elseif (CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(OS_SPECIFIC_FILES
        "window/linux/keys.h"
        "window/linux/window.h"
        "window/linux/window_init.h"
        "window/linux/wl_deleter.cc"
        "window/linux/wl_deleter.h"
        "window/linux/wl_window.cc"
        "window/linux/wl_window.h"
        "window/linux/x11_window.cc"
        "window/linux/x11_window.h"
    )
    set(VULKAN TRUE)
endif()

if (VULKAN)
    set(GPU_FILES
       "render/vk_renderer.cc"
       "render/vk_renderer.h"
       "gpu/vulkan/command_pool.cc"
       "gpu/vulkan/command_pool.h"
       "gpu/vulkan/descriptor_pool.cc"
       "gpu/vulkan/descriptor_pool.h"
       "gpu/vulkan/device.cc"
       "gpu/vulkan/device.h"
       "gpu/vulkan/image.cc"
       "gpu/vulkan/image.h"
       "gpu/vulkan/instance.cc"
       "gpu/vulkan/instance.h"
       "gpu/vulkan/pipeline.cc"
       "gpu/vulkan/pipeline.h"
       "gpu/vulkan/physical_device.cc"
       "gpu/vulkan/physical_device.h"
       "gpu/vulkan/status.h"
       "gpu/vulkan/shader.cc"
       "gpu/vulkan/shader.h"
       "gpu/vulkan/swapchain.cc"
       "gpu/vulkan/swapchain.h"
       "gpu/vulkan/buffer.cc"
       "gpu/vulkan/buffer.h"
    )
endif()

set(SOURCE_FILES
   "entity/player.cc"
   "entity/player.h"
   "geometry/circle.cc"
   "geometry/circle.h"
   "geometry/model.cc"
   "geometry/model.h"
   "geometry/shape.cc"
   "geometry/shape.h"
   "gpu/gpu.h"
   "image/png.cc"
   "image/png.h"
   "math/angle.h"
   "math/mat4.h"
   "math/vector.h"
   "render/model.h"
   "render/renderer.h"
   "render/ui.h"
   "ttf/reader.h"
   "ttf/ttf.cc"
   "ttf/ttf.h"
   "ui/font.cc"
   "ui/font.h"
   "ui/text.h"
   "ui/ui.cc"
   "ui/ui.h"
   "ui/widget.h"
   "util/assert.h"
   "util/bitfield.h"
   "util/libdeflate.h"
   "util/memory.h"
   "util/os_detect.h"
   "util/rand.h"
   "util/reader.h"
   "util/slab.h"
   "vendor/stb_image.h"
   "vendor/stb_truetype.h"
   "window/keys.h"
   "window/window.h"
   "app.cc"
   "app.h"
   "mesh.h"
   "stl.cc"
   "stl.h"
   ${OS_SPECIFIC_FILES}
   ${GPU_FILES}
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

function(embed_binary target file)
    add_custom_command(
        OUTPUT ${file}.h
        COMMAND xxd -i ${file} ${file}.h
        DEPENDS ${file}
        WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
    )

    target_sources(${target} PRIVATE ${file}.h)
endfunction()

function(embed_vulkan_shader target file)
    string(REGEX REPLACE "[/.]" "_" c_array_name ${file})
    get_filename_component(file_name ${file} NAME)
    set(destination ${CMAKE_CURRENT_LIST_DIR}/res/${file_name}.h)

    add_custom_command(
        OUTPUT ${destination}
        COMMAND glslc ${file} -o - | xxd -i -n ${c_array_name} > ${destination}
        DEPENDS ${file}
        WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
    )

    target_sources(${target} PRIVATE ${destination})
endfunction()

function(setup_targets subject)
    target_include_directories(${subject} PUBLIC "${PROJECT_SOURCE_DIR}/src")
    target_link_libraries(${subject} libdeflate_static)

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
        generate_wayland_protocol(${subject} /usr/share/wayland-protocols/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml)
    endif()

    if (WIN32 OR CMAKE_SYSTEM_NAME STREQUAL "Linux")
        embed_vulkan_shader(${subject} shader/text.vert)
        embed_vulkan_shader(${subject} shader/text.frag)
        embed_vulkan_shader(${subject} shader/model.vert)
        embed_vulkan_shader(${subject} shader/model.frag)
    endif()

    if (CMAKE_SYSTEM_NAME STREQUAL "Darwin")
        target_link_libraries(${subject}
            "-framework Foundation"
            "-framework AppKit"
            "-framework Metal"
            "-framework QuartzCore"
        )
    endif()

    embed_binary(${subject} res/arial.ttf)

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
