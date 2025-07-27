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

    pub fn poll(self: *Window) bool {
        return ffi.poll_window(self.handle);
    }

    pub fn setCaptureMouse(self: *Window, capture: bool) void {
        ffi.set_capture_mouse(self.handle, capture);
    }

    pub fn requestClose(self: *Window) void {
        ffi.request_close_window(self.handle);
    }

    pub fn getWidth(self: *const Window) i32 {
        return ffi.get_window_width(self.handle);
    }

    pub fn getHeight(self: *const Window) i32 {
        return ffi.get_window_height(self.handle);
    }

    pub fn getMouseX(self: *const Window) i32 {
        return ffi.get_mouse_x(self.handle);
    }

    pub fn getMouseY(self: *const Window) i32 {
        return ffi.get_mouse_y(self.handle);
    }

    pub fn getDeltaMouseX(self: *const Window) i32 {
        return ffi.get_delta_mouse_x(self.handle);
    }

    pub fn getDeltaMouseY(self: *const Window) i32 {
        return ffi.get_delta_mouse_y(self.handle);
    }

    pub fn isLeftClicking(self: *const Window) bool {
        return ffi.is_left_clicking(self.handle);
    }

    pub fn isKeyDown(self: *const Window, keyCode: u8) bool {
        return ffi.is_key_down(self.handle, keyCode);
    }

    pub fn keyJustPressed(self: *const Window, keyCode: u8) bool {
        return ffi.key_just_pressed(self.handle, keyCode);
    }

    pub fn getTypedChars(self: *const Window) []const u8 {
        const chars = ffi.get_typed_chars(self.handle);
        const length = ffi.get_typed_chars_length(self.handle);
        return chars[0..@intCast(length)];
    }

    pub fn surface(self: *const Window) *const anyopaque {
        return ffi.get_window_surface(self.handle);
    }
};
