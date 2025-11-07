const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const vkAssert = @import("status.zig").vkAssert;
const Gpu = @import("gpu.zig").Gpu;
const Device = @import("device.zig").Device;
const Surface = @import("surface.zig").Surface;

pub const Swapchain = struct {
    allocator: std.mem.Allocator,
    device: Device,
    gpu: Gpu,
    surface: Surface,
    width: u32,
    height: u32,
    swapchain: vk.VkSwapchainKHR = null,
    images: ?std.array_list.Aligned(vk.VkImage, null) = null,
    image_views: ?std.array_list.Aligned(vk.VkImageView, null) = null,
    image_format: ?vk.VkImageFormatProperties = null,
    image_extent: ?vk.VkExtent2D = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, gpu: Gpu, device: Device, surface: Surface, width: u32, height: u32) Self {
        return .{
            .allocator = allocator,
            .device = device,
            .gpu = gpu,
            .surface = surface,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *Self) void {
        self.images.?.deinit(self.allocator);
        self.dispose();
    }

    pub fn dispose(self: *Self) void {
        for (self.image_views.?.items) |view| {
            vk.vkDestroyImageView(self.device.device, view, null);
        }
        self.image_views.?.deinit(self.allocator);

        if (self.swapchain) |swapchain| {
            vk.vkDestroySwapchainKHR(self.device.device, swapchain, null);
            self.swapchain = null;
        }
    }

    pub fn createSwapchain(self: *Self, queue_families: []u32) vk.VkSwapchainKHR {
        const physical_device = self.gpu.physical_device;
        const device = self.device.device;
        const surface = self.surface.getSurface();

        var num_formats: u32 = 0;
        vk.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &num_formats, null);
        var format_list = std.ArrayList(vk.VkSurfaceFormatKHR).initCapacity(
            self.allocator,
            num_formats,
        ) catch @panic("OOM");
        defer format_list.deinit();
        vk.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &num_formats, format_list.items.ptr);

        var num_present_modes: u32 = 0;
        vk.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &num_present_modes, null);
        var present_modes = std.ArrayList(vk.VkPresentModeKHR).initCapacity(
            self.allocator,
            num_present_modes,
        ) catch @panic("OOM");
        defer present_modes.deinit();
        vk.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &num_present_modes, present_modes.items.ptr);

        var capabilities = vk.VkSurfaceCapabilitiesKHR{};
        vkAssert(vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities)) catch
            @panic("Could not get surface capabilities");

        const image_count: u32 = capabilities.minImageCount + 1;
        if (capabilities.maxImageCount != 0 and image_count > capabilities.maxImageCount) {
            image_count = capabilities.maxImageCount;
        }

        const best_format = findBestSurfaceFormat(format_list.items);
        self.image_format = best_format;

        self.image_extent = createExtent(capabilities, self.width, self.height);

        var swapchain_create_info = vk.VkSwapchainCreateInfoKHR{
            .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = surface,
            .minImageCount = image_count,
            .imageFormat = best_format.format,
            .imageColorSpace = best_format.colorSpace,
            .imageExtent = self.image_extent.?,
            .imageArrayLayers = 1,
            .imageUsage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .preTransform = capabilities.currentTransform,
            .compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = findBestPresentMode(present_modes.items),
            .clipped = vk.VK_TRUE,
        };

        if (queue_families[0] != queue_families[1]) {
            swapchain_create_info.imageSharingMode = vk.VK_SHARING_MODE_CONCURRENT;
            swapchain_create_info.queueFamilyIndexCount = queue_families.len;
            swapchain_create_info.pQueueFamilyIndices = queue_families.ptr;
        }

        const swapchain_result = vk.vkCreateSwapchainKHR(
            device,
            &swapchain_create_info,
            null,
            &self.swapchain,
        );
        vkAssert(swapchain_result) catch std.debug.panic("Could not create swapchain ({})", .{swapchain_result});

        var num_images: u32 = 0;
        vk.vkGetSwapchainImagesKHR(device, self.swapchain, &num_images, null);
        self.images = std.ArrayList(vk.VkImage).initCapacity(self.allocator, num_images);
        self.images.?.resize(self.allocator, num_images);
        vk.vkGetSwapchainImagesKHR(device, self.swapchain, &num_images, self.images.?.items.ptr);

        self.image_views = std.ArrayList(vk.VkImageView).initCapacity(self.allocator, num_images);
        self.image_views.?.resize(self.allocator, num_images);
        for (0..num_images) |i| {
            const create_info = vk.VkImageViewCreateInfo{
                .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = self.images.items[i],
                .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
                .format = self.image_format,
                .subresourceRange = .{
                    .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                    .levelCount = 1,
                    .layerCount = 1,
                },
            };

            const result = vk.vkCreateImageView(device, &create_info, null, &self.image_views.?.items[i]);
            vkAssert(result) catch std.debug.panic("Failed to create ImageView ({})\n", .{result});
        }
    }

    pub fn isSupportedOn(physical_device: vk.VkPhysicalDevice, surface: vk.VkSurfaceKHR) bool {
        if (!hasSwapchainSupport(physical_device)) {
            return false;
        }

        var num_formats: u32 = 0;
        vk.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &num_formats, null);
        var num_present_modes: u32 = 0;
        vk.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &num_present_modes, null);
        return num_formats > 1 and num_present_modes > 1;
    }

    fn hasSwapchainSupport(physical_device: vk.VkPhysicalDevice) bool {
        var num_extensions: u32 = 0;
        vk.vkEnumerateDeviceExtensionProperties(physical_device, null, &num_extensions, null);
        const extensions = std.heap.page_allocator.alloc(vk.VkExtensionProperties, num_extensions) catch
            @panic("OOM");
        defer std.heap.page_allocator.free(extensions);
        vk.vkEnumerateDeviceExtensionProperties(physical_device, null, &num_extensions, extensions.ptr);

        for (extensions) |extension| {
            if (std.mem.eql([]u8, extension.extensionName, vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME)) {
                return true;
            }
        }

        return false;
    }

    fn findBestSurfaceFormat(formats: []vk.VkSurfaceFormatKHR) vk.VkSurfaceFormatKHR {
        for (formats) |format| {
            if (format.format == vk.VK_FORMAT_R8G8B8A8_SRGB and format.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                return format;
            }
        }

        return formats[0];
    }

    fn findBestPresentMode(present_modes: []vk.VkPresentModeKHR) vk.VkPresentModeKHR {
        for (present_modes) |mode| {
            if (mode == vk.VK_PRESENT_MODE_MAILBOX_KHR) {
                return mode;
            }
        }

        return vk.VK_PRESENT_MODE_FIFO_KHR;
    }

    fn createExtent(capabilities: vk.VkSurfaceCapabilitiesKHR, width: u32, height: u32) vk.VkExtent3D {
        var extent = capabilities.currentExtent;

        if (capabilities.currentExtent.width == @as(u32, -1)) {
            extent.width = std.math.clamp(width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
            extent.height = std.math.clamp(height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height);
        }

        return extent;
    }
};
