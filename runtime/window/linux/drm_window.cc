#include "drm_window.h"

#include <vulkan/vulkan_core.h>

#include <cstdint>
#include <cstring>
#include <format>
#include <stdexcept>
#include <vector>

#include "gpu/vulkan/status.h"

using namespace simulo;

Window::Window(const Gpu &vk_instance, const char *display_name) {
    uint32_t n_displays;
    VKAD_VK(vkGetPhysicalDeviceDisplayProperties2KHR(vk_instance.physical_device(), &n_displays, nullptr));

    std::vector<VkDisplayProperties2KHR> displays(n_displays);
    VKAD_VK(vkGetPhysicalDeviceDisplayProperties2KHR(vk_instance.physical_device(), &n_displays, displays.data()));

    bool found = false;
    for (const auto &display : displays) {
        if (std::strcmp(display.displayProperties.displayName, display_name) == 0) {
            display_ = display.displayProperties.display;
            width_ = static_cast<int>(display.displayProperties.physicalResolution.width);
            height_ = static_cast<int>(display.displayProperties.physicalResolution.height);
            found = true;
            break;
        }
    }

    if (!found) {
        throw std::runtime_error(std::format("display {} not found. options: {}", display_name, displays));
    }

    best_display_mode(display_);
    /*VkDisplaySurfaceCreateInfoKHR create_info = {
        .sType = VK_STRUCTURE_TYPE_DISPLAY_SURFACE_CREATE_INFO_KHR,
        .pNext = nullptr,
        .flags = 0,
        .displayMode = best_display_mode(display_),
    };

    vkCreateDisplayPlaneSurfaceKHR(vk_instance.instance(), &vk_create_info, nullptr, &surface_);*/
}

VkDisplayModeKHR best_display_mode(VkDisplayKHR display) {
    uint32_t n_modes;
    VKAD_VK(vkGetDisplayModePropertiesKHR(vk_instance.physical_device(), display, &n_modes, nullptr));

    std::vector<VkDisplayModePropertiesKHR> modes(n_modes);
    VKAD_VK(vkGetDisplayModePropertiesKHR(vk_instance.physical_device(), display, &n_modes, modes.data()));

    throw std::runtime_error(std::format("modes: {}", modes));
}