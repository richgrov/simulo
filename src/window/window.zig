const Gpu = @import("../gpu/gpu.zig").Gpu;

const ffi = @cImport({
    @cInclude("ffi.h");
});

pub const Window = struct {
    handle: *ffi.Window,

    pub fn init(gpu: *const Gpu, title: []const u8) Window {
        return Window{
            .handle = ffi.create_window(gpu.handle, @ptrCast(title)).?,
        };
    }

    pub fn deinit(self: *Window) void {
        ffi.destroy_window(self.handle);
    }
};
