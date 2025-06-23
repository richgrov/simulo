const ffi = @cImport({
    @cInclude("ffi.h");
});

pub const Gpu = struct {
    handle: *ffi.Gpu,

    pub fn init() Gpu {
        return Gpu{ .handle = ffi.create_gpu().? };
    }

    pub fn deinit(self: Gpu) void {
        ffi.destroy_gpu(self.handle);
    }
};
