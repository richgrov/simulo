const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const vkAssert = @import("status.zig").vkAssert;
const ffi = @import("ffi");
const Gpu = @import("gpu.zig").Gpu;

pub const Surface = struct {
    gpu: *ffi.Gpu,
    window: *ffi.Window,

    const Self = @This();

    pub fn init(gpu: Gpu, title: [*c]const u8) Self {
        const gpu_properties = ffi.GpuWrapper{
            .instance_ = @ptrCast(gpu.instance),
            .physical_device_ = @ptrCast(gpu.physical_device),
            .min_uniform_alignment_ = gpu.min_uniform_alignment,
            .mem_properties_ = ffi_mem_properties(gpu.memory_properties),
            .graphics_queue_ = gpu.graphics_queue,
            .present_queue_ = gpu.present_queue,
        };
        const simulo_gpu = ffi.create_gpu(gpu_properties).?;
        const simulo_window = ffi.create_window(simulo_gpu, title);

        return .{
            .gpu = simulo_gpu,
            .window = simulo_window.?,
        };
    }

    fn ffi_mem_properties(gpu_memory_properties: vk.VkPhysicalDeviceMemoryProperties) ffi.VkPhysicalDeviceMemoryProperties {
        var ffi_memory_heaps = std.mem.zeroes([16]ffi.VkMemoryHeap);
        for (gpu_memory_properties.memoryHeaps, 0..) |memory_heap, i| {
            ffi_memory_heaps[i].flags = memory_heap.flags;
            ffi_memory_heaps[i].size = memory_heap.size;
        }

        var ffi_memory_types = std.mem.zeroes([32]ffi.VkMemoryType);
        for (gpu_memory_properties.memoryTypes, 0..) |memory_type, i| {
            ffi_memory_types[i].heapIndex = memory_type.heapIndex;
            ffi_memory_types[i].propertyFlags = memory_type.propertyFlags;
        }

        return ffi.VkPhysicalDeviceMemoryProperties{
            .memoryHeapCount = gpu_memory_properties.memoryHeapCount,
            .memoryHeaps = ffi_memory_heaps,
            .memoryTypeCount = gpu_memory_properties.memoryTypeCount,
            .memoryTypes = ffi_memory_types,
        };
    }

    pub fn deinit(self: Self) void {
        ffi.destroy_window(self.window);
        // vk.vkDestroySurfaceKHR(instance, self.surface, null);
    }

    pub fn getSurface(self: Self) vk.VkSurfaceKHR {
        ffi.get_window_surface(self.window).?;
    }

    pub fn poll(self: *Self) bool {
        return ffi.poll_window(self.window);
    }

    pub fn setCaptureMouse(self: *Self, capture: bool) void {
        ffi.set_capture_mouse(self.window, capture);
    }

    pub fn requestClose(self: *Self) void {
        ffi.request_close_window(self.window);
    }

    pub fn getWidth(self: *const Self) i32 {
        return ffi.get_window_width(self.window);
    }

    pub fn getHeight(self: *const Self) i32 {
        return ffi.get_window_height(self.window);
    }

    pub fn getMouseX(self: *const Self) i32 {
        return ffi.get_mouse_x(self.window);
    }

    pub fn getMouseY(self: *const Self) i32 {
        return ffi.get_mouse_y(self.window);
    }

    pub fn getDeltaMouseX(self: *const Self) i32 {
        return ffi.get_delta_mouse_x(self.window);
    }

    pub fn getDeltaMouseY(self: *const Self) i32 {
        return ffi.get_delta_mouse_y(self.window);
    }

    pub fn isLeftClicking(self: *const Self) bool {
        return ffi.is_left_clicking(self.window);
    }

    pub fn isKeyDown(self: *const Self, keyCode: u8) bool {
        return ffi.is_key_down(self.window, keyCode);
    }

    pub fn keyJustPressed(self: *const Self, keyCode: u8) bool {
        return ffi.key_just_pressed(self.window, keyCode);
    }

    pub fn getTypedChars(self: *const Self) []const u8 {
        const chars = ffi.get_typed_chars(self.window);
        const length = ffi.get_typed_chars_length(self.window);
        return chars[0..@intCast(length)];
    }

    pub fn surface(self: *const Self) *anyopaque {
        return ffi.get_window_surface(self.window).?;
    }
};
