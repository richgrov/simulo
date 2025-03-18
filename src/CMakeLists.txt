if (CMAKE_SYSTEM_NAME STREQUAL "Linux")
    find_package(X11 REQUIRED)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(WAYLAND REQUIRED wayland-client wayland-protocols)
    pkg_check_modules(XKBCOMMON REQUIRED xkbcommon)
endif()

if (WIN32)
    set(PLATFORM_FILES ${PLATFORM_FILES}
        "window/win32/keys.h"
        "window/win32/window.cc"
        "window/win32/window.h"
    )
    set(VULKAN TRUE)
elseif (CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(PLATFORM_FILES ${PLATFORM_FILES}
        "gpu/metal/buffer.h"
        "gpu/metal/buffer.mm"
        "gpu/metal/command_queue.h"
        "gpu/metal/command_queue.mm"
        "gpu/metal/gpu.h"
        "gpu/metal/gpu.mm"
        "render/mt_renderer.h"
        "render/mt_renderer.mm"
        "window/macos/window.h"
        "window/macos/window.mm"
    )
elseif (CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(PLATFORM_FILES ${PLATFORM_FILES}
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
    set(PLATFORM_FILES ${PLATFORM_FILES}
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

add_library(vkad_common
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
   "math/matrix.h"
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
   "util/rational.h"
   "util/rational.cc"
   "vendor/stb_image.h"
   "vendor/stb_truetype.h"
   "window/keys.h"
   "window/window.h"
   "app.cc"
   "app.h"
   "mesh.h"
   "stl.cc"
   "stl.h"
   ${PLATFORM_FILES}
)

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

function(embed_metal_shader target file)
    get_filename_component(file_name ${file} NAME_WE)
    set(output "${CMAKE_CURRENT_BINARY_DIR}/default.metallib")
    
    add_custom_command(
        OUTPUT ${output}
        COMMAND xcrun -sdk macosx metal -c ${file} -o ${CMAKE_CURRENT_BINARY_DIR}/${file_name}.air
        COMMAND xcrun -sdk macosx metallib ${CMAKE_CURRENT_BINARY_DIR}/${file_name}.air -o ${output} 
        DEPENDS ${file}
        WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
    )

    # Add the metallib to the bundle's resources
    set_source_files_properties(${output} PROPERTIES 
        MACOSX_PACKAGE_LOCATION "Resources"
        XCODE_EXPLICIT_FILE_TYPE "com.apple.metal-library"
    )
    target_sources(${target} PUBLIC ${output})
endfunction()

target_include_directories(vkad_common PUBLIC "${PROJECT_SOURCE_DIR}/src")
target_link_libraries(vkad_common libdeflate_static)

# Vulkan
if (WIN32)
    target_link_directories(vkad_common PUBLIC "$ENV{VULKAN_SDK}/Lib")
    target_link_libraries(vkad_common "vulkan-1.lib")
    target_include_directories(vkad_common PUBLIC "$ENV{VULKAN_SDK}/Include")
elseif (CMAKE_SYSTEM_NAME STREQUAL "Linux")
    target_link_libraries(vkad_common libvulkan.so)
endif()

if (CMAKE_SYSTEM_NAME STREQUAL "Linux")
    target_include_directories(vkad_common PRIVATE ${X11_INCLUDE_DIR})
    target_link_libraries(vkad_common ${X11_LIBRARIES} libXi.so)

    target_include_directories(vkad_common PRIVATE ${WAYLAND_INCLUDE_DIRS})
    target_link_libraries(vkad_common ${WAYLAND_LIBRARIES})

    target_include_directories(vkad_common PRIVATE ${XKBCOMMON_INCLUDE_DIRS})
    target_link_directories(vkad_common PRIVATE ${XKBCOMMON_LIBRARY_DIRS})
    target_link_libraries(vkad_common ${XKBCOMMON_LIBRARIES})

    generate_wayland_protocol(vkad_common /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml)
    generate_wayland_protocol(vkad_common /usr/share/wayland-protocols/unstable/relative-pointer/relative-pointer-unstable-v1.xml)
    generate_wayland_protocol(vkad_common /usr/share/wayland-protocols/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml)
endif()

if (WIN32 OR CMAKE_SYSTEM_NAME STREQUAL "Linux")
    embed_vulkan_shader(vkad_common shader/text.vert)
    embed_vulkan_shader(vkad_common shader/text.frag)
    embed_vulkan_shader(vkad_common shader/model.vert)
    embed_vulkan_shader(vkad_common shader/model.frag)
elseif (CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    embed_metal_shader(vkad_common shader/text.metal)

    target_link_libraries(vkad_common
        "-framework Foundation"
        "-framework AppKit"
        "-framework Metal"
        "-framework QuartzCore"
    )
endif()


embed_binary(vkad_common res/arial.ttf)
target_compile_features(vkad_common PUBLIC cxx_std_20)

add_executable(vkad "main.cc")
target_link_libraries(vkad vkad_common)
target_compile_features(vkad PUBLIC cxx_std_20)
set_target_properties(vkad PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.vkad.app"
)


set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -DVKAD_DEBUG")

if (BUILD_TESTING)
    add_executable(vkad_test
        "test_main.cc"
        "math/angle_test.cc"
        "math/matrix_test.cc"
        "math/vector_test.cc"
    )
    target_link_libraries(vkad_test vkad_common)
    set_target_properties(vkad_test PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.vkad.app"
    )
endif()
