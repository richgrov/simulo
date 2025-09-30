const ffi = @cImport({
    @cInclude("tracking/bindings.h");
});

pub const Object = ffi.BtInput;

pub const ByteTracker = struct {
    handle: *ffi.BYTETracker,
    output_buf: [128]i32 = undefined,

    pub fn init(frame_rate: i32, track_buffer: i32) ByteTracker {
        return ByteTracker{ .handle = ffi.create_byte_tracker(frame_rate, track_buffer).? };
    }

    pub fn deinit(self: *ByteTracker) void {
        ffi.destroy_byte_tracker(self.handle);
    }

    pub fn update(self: *ByteTracker, objects: []Object) []const i32 {
        const len = ffi.update_byte_tracker(self.handle, objects.ptr, @intCast(objects.len), &self.output_buf, @intCast(self.output_buf.len));
        return self.output_buf[0..@intCast(len)];
    }
};
