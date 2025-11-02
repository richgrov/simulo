const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const vkAssert = @import("status.zig").vkAssert;
const ffi = @import("ffi");
const Gpu = @import("physical_device.zig").Gpu;

pub const Surface = struct {
    gpu: *ffi.Gpu,
    window: *ffi.Window,

    const Self = @This();

    pub fn init(gpu: Gpu, title: [*c]const u8) Self {
        const gpu_properties = ffi.GpuWrapper{
            .instance_ = gpu.instance,
            .physical_device_ = gpu.physical_device,
            .min_uniform_alignment_ = gpu.min_uniform_alignment,
            .mem_properties_ = gpu.mem_properties,
            .graphics_queue_ = gpu.graphics_queue,
            .present_queue_ = gpu.present_queue,
        };
        const simulo_gpu = ffi.create_gpu(gpu_properties).?;
        const simulo_window = ffi.create_window(simulo_gpu, title);

        return .{
            .gpu = simulo_gpu,
            .window = simulo_window,
        };
    }

    pub fn deinit(self: Self, instance: vk.VkInstance) void {
        vk.vkDestroySurfaceKHR(instance, self.surface, null);
    }

    pub fn getSurface(self: Self) vk.VkSurfaceKHR {
        ffi.get_window_surface(self.window).?;
    }
};
