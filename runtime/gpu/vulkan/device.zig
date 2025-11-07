const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const vk = @import("vulkan");
const vkAssert = @import("status.zig").vkAssert;
const Gpu = @import("gpu.zig").Gpu;
const validation_layers = @import("validation_layers.zig").validation_layers;

pub const Device = struct {
    allocator: std.mem.Allocator,
    device: vk.VkDevice,
    graphics_queue: vk.VkQueue,
    present_queue: vk.VkQueue,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, gpu: Gpu) Self {
        var unique_queue_families = std.AutoHashMap(u32, void).init(allocator);
        defer unique_queue_families.deinit();

        unique_queue_families.put(gpu.graphics_queue, {});
        unique_queue_families.put(gpu.present_queue, {});

        var create_queues = std.ArrayList(vk.VkDeviceQueueCreateInfo).initCapacity(allocator, unique_queue_families.capacity()) catch
            @panic("OOM");
        defer create_queues.deinit(allocator);

        const priority: f32 = 1.0;
        var unique_queue_families_iter = unique_queue_families.keyIterator();
        while (unique_queue_families_iter.next()) |queue_family| {
            const create_info = vk.VkDeviceQueueCreateInfo{
                .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = queue_family,
                .queueCount = 1,
                .pQueuePriorities = &priority,
            };
            create_queues.append(allocator, create_info);
        }

        const device_create_info = vk.VkDeviceCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .queueCreateInfoCount = create_queues.len,
            .pQueueCreateInfos = create_queues.items.ptr,
            .enabledExtensionCount = 1,
            .ppEnabledExtensionNames = vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
            .enabledLayerCount = validation_layers.len,
            .ppEnabledLayerNames = &validation_layers[0],
        };

        var device = vk.VkDevice{};
        vkAssert(vk.vkCreateDevice(gpu.physical_device, &device_create_info, null, &device));

        var graphics_queue = vk.VkQueue{};
        var present_queue = vk.VkQueue{};
        vk.vkGetDeviceQueue(device, gpu.graphics_queue, 0, &graphics_queue);
        vk.vkGetDeviceQueue(device, gpu.present_queue, 0, &present_queue);

        return .{
            .allocator = allocator,
            .device = device,
            .graphics_queue = graphics_queue,
            .present_queue = present_queue,
        };
    }

    pub fn deinit(self: *Self) void {
        vk.vkDestroyDevice(self.device, null);
    }
};
