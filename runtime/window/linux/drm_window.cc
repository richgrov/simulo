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

VkDisplayModeKHR best_display_mode(VkPhysicalDevice physical_device, VkDisplayKHR display, VkExtent2D *out_extent) {
    uint32_t n_modes;
    VKAD_VK(vkGetDisplayModePropertiesKHR(physical_device, display, &n_modes, nullptr));

    if (n_modes == 0) {
        throw std::runtime_error("no display modes found");
    }

    std::vector<VkDisplayModePropertiesKHR> modes(n_modes);
    VKAD_VK(vkGetDisplayModePropertiesKHR(physical_device, display, &n_modes, modes.data()));

    VkExtent2D biggest_size = {0, 0};
    uint32_t greatest_refresh_rate = 0;
    VkDisplayModeKHR best_mode;

    for (const auto &mode : modes) {
        if (mode.parameters.visibleRegion.width > biggest_size.width) {
            biggest_size = mode.parameters.visibleRegion;
            greatest_refresh_rate = mode.parameters.refreshRate;
            best_mode = mode.displayMode;
        } else if (mode.parameters.visibleRegion.width == biggest_size.width && mode.parameters.refreshRate > greatest_refresh_rate) {
            biggest_size = mode.parameters.visibleRegion;
            greatest_refresh_rate = mode.parameters.refreshRate;
            best_mode = mode.displayMode;
        }
    }

    *out_extent = biggest_size;
    return best_mode;
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

    uint32_t n_planes;
    VKAD_VK(vkGetPhysicalDeviceDisplayPlanePropertiesKHR(gpu.physical_device(), &n_planes, nullptr));

    std::vector<VkDisplayPlanePropertiesKHR> planes(n_planes);
    VKAD_VK(vkGetPhysicalDeviceDisplayPlanePropertiesKHR(gpu.physical_device(), &n_planes, planes.data()));

    const uint32_t plane = 0;

    VkExtent2D extent;
    VkDisplayModeKHR display_mode = best_display_mode(gpu.physical_device(), display_, &extent_);
    VkDisplaySurfaceCreateInfoKHR create_info = {
        .sType = VK_STRUCTURE_TYPE_DISPLAY_SURFACE_CREATE_INFO_KHR,
        .pNext = nullptr,
        .flags = 0,
        .displayMode = display_mode,
        .planeIndex = plane,
        .planeStackIndex = planes[plane].currentStackIndex,
        .transform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
        .alphaMode = VK_DISPLAY_PLANE_ALPHA_GLOBAL_BIT_KHR,
        .imageExtent = extent,
    };

    vkCreateDisplayPlaneSurfaceKHR(gpu.instance(), &create_info, nullptr, &surface_);
}

Window::~Window() {
    vkDestroySurfaceKHR(gpu.instance(), surface_, nullptr);
}