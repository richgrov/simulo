// TODO: To be renamed to gpu.zig once all of the migration is finished
// TODO: Didn't want to do it now because of gpu.zig that's in the parent directory

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const vk = @import("vulkan");
const vkAssert = @import("status.zig").vkAssert;
const Surface = @import("surface.zig").Surface;

const validation_layers = [_][256]u8{"VK_LAYER_KHRONOS_validation"};

fn ensureLayersAreSupported(allocator: std.mem.Allocator) void {
    var total_layers: u32 = 0;
    vk.vkEnumerateInstanceLayerProperties(&total_layers, null);

    var layers = std.ArrayList(vk.VkLayerProperties).initCapacity(allocator, total_layers) catch @panic("OOM");
    layers.resize(allocator, total_layers);
    vk.vkEnumerateInstanceLayerProperties(&total_layers, layers.items.ptr);

    for (validation_layers) |needed_layer| {
        var exists = false;
        for (layers.items) |available_layer| {
            if (std.mem.eql(u8, needed_layer, available_layer.layerName)) {
                exists = true;
                break;
            }
        }

        if (!exists) {
            std.debug.panic("Validation layer {s} is not supported\n", .{needed_layer});
        }
    }
}

pub const Gpu = struct {
    allocator: std.mem.Allocator,
    instance: vk.VkInstance = null,
    physical_device: vk.VkPhysicalDevice = null,
    surface: ?Surface = null,
    memory_properties: vk.VkPhysicalDeviceMemoryProperties = null,
    min_uniform_alignment: vk.VkDeviceSize = 0,
    graphics_queue: u32 = 0,
    present_queue: u32 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: Self) void {
        self.surface.?.deinit(self.instance);
        vk.vkDestroyInstance(self.instance, null);
    }

    pub fn initVulkan(self: Self) void {
        self.createInstance();
        self.getPhysicalDevice();
        self.surface = Surface.init(self.instance);
        self.findQueueFamilies();
    }

    fn createInstance(self: Self) void {
        const application_create_info = vk.VkApplicationInfo{
            .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .applicationVersion = vk.VK_MAKE_VERSION(1, 0, 0),
            .engineVersion = vk.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = vk.VK_API_VERSION_1_0,
        };

        const extensions = switch (builtin.os.tag) {
            .windows => [_][*c]const u8{
                vk.VK_KHR_SURFACE_EXTENSION_NAME,
                "VK_KHR_win32_surface",
            },
            .macos => [_][*c]const u8{
                vk.VK_KHR_SURFACE_EXTENSION_NAME,
                vk.VK_EXT_METAL_SURFACE_EXTENSION_NAME,
            },
            .linux => [_][*c]const u8{
                vk.VK_KHR_SURFACE_EXTENSION_NAME,
                "VK_KHR_display",
                "VK_KHR_get_display_properties2",
            },
            else => |os| std.debug.panic("OS not supported {any}\n", .{os}),
        };

        var instance_create_info = vk.VkInstanceCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &application_create_info,
            .enabledExtensionCount = extensions.len,
            .ppEnabledExtensionNames = extensions.ptr,
        };

        if (build_options.debug_vulkan) {
            ensureLayersAreSupported();
            instance_create_info.enabledLayerCount = @intCast(validation_layers.len);
            instance_create_info.ppEnabledLayerNames = &validation_layers[0];
            std.debug.print("Validation layers enabled", .{});
        }

        const vulkan_instance_result = vk.vkCreateInstance(&instance_create_info, null, &self.instance);
        vkAssert(vulkan_instance_result) catch std.debug.panic("Could not create Vulkan instance: {}\n", .{vulkan_instance_result});
    }

    fn getPhysicalDevice(self: Self) void {
        var physical_device_count: u32 = 0;
        vk.vkEnumeratePhysicalDevices(self.instance, &physical_device_count, null);

        if (physical_device_count == 0) {
            @panic("There are no physical devices");
        }

        var physical_devices = std.ArrayList(vk.VkPhysicalDevice).initCapacity(
            self.allocator,
            physical_device_count,
        ) catch @panic("OOM");
        defer physical_devices.deinit(self.allocator);
        physical_devices.resize(self.allocator, physical_device_count);
        vk.vkEnumeratePhysicalDevices(self.instance, &physical_device_count, physical_devices.items.ptr);

        var highest_score: u32 = 0;
        for (physical_devices.items) |physical_device| {
            var score: u32 = 0;

            var properties = vk.VkPhysicalDeviceProperties{};
            vk.vkGetPhysicalDeviceProperties(physical_device, &properties);

            if (properties.deviceType == vk.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
                score += 10;
            }

            if (score >= highest_score) {
                highest_score = score;
                self.physical_device = physical_device;
                self.min_uniform_alignment = properties.limits.minUniformBufferOffsetAlignment;
                vk.vkGetPhysicalDeviceMemoryProperties(physical_device, &self.memory_properties);
            }
        }
    }

    fn findQueueFamilies(self: Self) void {
        var queue_family_count: u32 = 0;
        vk.vkGetPhysicalDeviceQueueFamilyProperties(self.physical_device, &queue_family_count, null);

        var queue_families = std.ArrayList(vk.VkQueueFamilyProperties).initCapacity(
            self.allocator,
            queue_family_count,
        ) catch @panic("OOM");
        defer queue_families.deinit(self.allocator);
        vk.vkGetPhysicalDeviceQueueFamilyProperties(
            self.physical_device,
            queue_family_count,
            queue_families.items.ptr,
        );

        var graphics_found = false;
        var present_found = false;
        for (0..queue_families.items.len) |i| {
            if (!graphics_found and queue_families.items[i].queueFlags & vk.VK_QUEUE_GRAPHICS_BIT != 0) {
                self.graphics_queue = @intCast(i);
                graphics_found = true;
            }

            if (!present_found) {
                var supported = false;
            }
        }
    }
};
