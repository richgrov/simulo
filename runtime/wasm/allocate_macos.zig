const std = @import("std");
const builtin = @import("builtin");

const PROT = std.posix.PROT;
const MAP_PRIVATE = 0x2;
const MAP_JIT = 0x800;
const MAP_ANONYMOUS = 0x1000;
const MAP_FAILED: *anyopaque = @ptrFromInt(0xFFFFFFFFFFFFFFFF);

extern fn mmap(addr: ?*anyopaque, len: usize, prot: c_int, flags: c_int, fd: c_int, offset: usize) callconv(.c) *align(16) anyopaque;
extern fn munmap(addr: *anyopaque, len: usize) callconv(.c) c_int;
extern fn pthread_jit_write_protect_np(enable: c_int) callconv(.c) void;
extern fn sys_icache_invalidate(addr: *anyopaque, len: usize) callconv(.c) void;

pub fn allocateExecutable(len: usize) !*anyopaque {
    const ptr = mmap(null, len, PROT.EXEC | PROT.WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_JIT, -1, 0);
    if (ptr == MAP_FAILED) {
        return error.MmapFailed;
    }

    pthread_jit_write_protect_np(0);
    return ptr;
}

pub fn finishAllocation(ptr: *anyopaque, len: usize) void {
    pthread_jit_write_protect_np(1);
    sys_icache_invalidate(ptr, len);
}

pub fn free(ptr: *anyopaque, len: usize) !void {
    if (munmap(ptr, len) != 0) {
        return error.MunmapFailed;
    }
}
