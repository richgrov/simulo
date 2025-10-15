#include "drm_window.h"

#include <vulkan/vulkan_core.h>

#include <cstdint>
#include <cstring>
#include <format>
#include <iostream>
#include <stdexcept>
#include <vector>

#include "gpu/vulkan/status.h"

using namespace simulo;

VkDisplayModeKHR best_display_mode(VkPhysicalDevice physical_device, VkDisplayKHR display) {
    uint32_t n_modes;
    VKAD_VK(vkGetDisplayModePropertiesKHR(physical_device, display, &n_modes, nullptr));

    std::vector<VkDisplayModePropertiesKHR> modes(n_modes);
    VKAD_VK(vkGetDisplayModePropertiesKHR(physical_device, display, &n_modes, modes.data()));

    for (const auto &mode : modes) {
        std::cout << std::format(
            "mode: {}x{}, {}Hz\n",
            mode.parameters.visibleRegion.width,
            mode.parameters.visibleRegion.height,
            mode.parameters.refreshRate
        );
    }
    std::cout.flush();
    throw std::runtime_error("not implemented");
}

Window::Window(const Gpu &gpu, const char *window_title) {
    (void)window_title;

    uint32_t n_displays;
    VKAD_VK(vkGetPhysicalDeviceDisplayProperties2KHR(gpu.physical_device(), &n_displays, nullptr));

    std::vector<VkDisplayProperties2KHR> displays(n_displays);
    VKAD_VK(vkGetPhysicalDeviceDisplayProperties2KHR(gpu.physical_device(), &n_displays, displays.data()));

    // Code is structured like this in case we want to add conditions in the loop later on
    bool found = false;
    for (const auto &display : displays) {
        display_ = display.displayProperties.display;
        width_ = static_cast<int>(display.displayProperties.physicalResolution.width);
        height_ = static_cast<int>(display.displayProperties.physicalResolution.height);
        found = true;
        break;
    }

    if (!found) {
        for (const auto &display : displays) {
            std::cout << std::format(
                "display '{}', {}x{}\n",
                display.displayProperties.displayName,
                display.displayProperties.physicalResolution.width,
                display.displayProperties.physicalResolution.height
            );
        }
        std::cout.flush();
        throw std::runtime_error(std::format("display not found"));
    }

    best_display_mode(gpu.physical_device(), display_);
    /*VkDisplaySurfaceCreateInfoKHR create_info = {
        .sType = VK_STRUCTURE_TYPE_DISPLAY_SURFACE_CREATE_INFO_KHR,
        .pNext = nullptr,
        .flags = 0,
        .displayMode = best_display_mode(gpu.physical_device(), display_),
    };

    vkCreateDisplayPlaneSurfaceKHR(gpu.instance(), &vk_create_info, nullptr, &surface_);*/
}