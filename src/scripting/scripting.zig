const pocketpy = @cImport({
    @cInclude("vendor/pocketpy/pocketpy.h");
});

pub const Scripting = struct {
    pub fn init() Scripting {
        pocketpy.py_initialize();
        return .{};
    }

    pub fn deinit(_: *const Scripting) void {
        pocketpy.py_finalize();
    }

    pub fn defineModule(_: *const Scripting, name: []const u8) void {
        _ = pocketpy.py_newmodule(@ptrCast(name)).?;
    }

    pub fn run(_: *const Scripting, src: []const u8, file: []const u8) !void {
        if (!pocketpy.py_exec(@ptrCast(src), @ptrCast(file), pocketpy.EXEC_MODE, null)) {
            return error.PythonError;
        }
    }
};
