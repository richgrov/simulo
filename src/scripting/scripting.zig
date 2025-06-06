const std = @import("std");

const reflect = @import("../util/util.zig").reflect;

const pocketpy = @cImport({
    @cInclude("vendor/pocketpy/pocketpy.h");
});

fn typeToPyType(T: type) c_int {
    if (T == Scripting.Function) {
        return pocketpy.tp_function;
    }

    return switch (@typeInfo(T)) {
        else => @compileError(@typeName(T) ++ " cannot be converted to Python type"),
    };
}

pub const Scripting = struct {
    pub const Value = *pocketpy.py_TValue;
    pub const NativeCallback = pocketpy.py_CFunction;
    pub const Function = struct {
        value: *pocketpy.py_TValue,
    };

    pub fn init(user_data: *anyopaque) Scripting {
        pocketpy.py_initialize();
        pocketpy.py_setvmctx(user_data);
        return .{};
    }

    pub fn deinit(_: *const Scripting) void {
        pocketpy.py_finalize();
    }

    pub fn defineModule(_: *const Scripting, name: []const u8) Value {
        return pocketpy.py_newmodule(@ptrCast(name)).?;
    }

    pub fn createFunction(_: *const Scripting, func: anytype) NativeCallback {
        const func_info = switch (@typeInfo(@TypeOf(func))) {
            .@"fn" => |f| f,
            else => @compileError("non-function passed to createFunction"),
        };

        const params = func_info.params;
        if (params.len < 1) {
            @compileError("all native functions must accept at least one parameter for a context pointer");
        }

        const py_argc = params.len - 1;

        const Funcs = struct {
            fn callback(argc: c_int, argv: pocketpy.py_StackRef) callconv(.C) bool {
                const argc_usize: usize = @intCast(argc);
                if (argc_usize != py_argc) {
                    return pocketpy.py_exception(
                        pocketpy.tp_TypeError,
                        "expected %d arguments, got %d",
                        py_argc,
                        argc,
                    );
                }

                const ZigArgs = reflect.functionParamsIntoTuple(params);
                var args: ZigArgs = undefined;
                args[0] = pocketpy.py_getvmctx().?;

                inline for (0..py_argc) |i| {
                    const py_type = comptime typeToPyType(params[i + 1].type.?);
                    if (!pocketpy.py_checktype(pocketpy.py_offset(argv, i), @intCast(py_type))) {
                        return false;
                    }

                    const value = pocketpy.py_offset(argv, i).?;

                    if (py_type == pocketpy.tp_function) {
                        const name = pocketpy.py_name("todo");
                        pocketpy.py_setglobal(name, value);
                        const persistent_value = pocketpy.py_getglobal(name).?;
                        args[i + 1] = Function{ .value = persistent_value };
                    } else {
                        unreachable;
                    }
                }

                @call(.auto, func, args);
                pocketpy.py_newnone(pocketpy.py_retval());
                return true;
            }
        };
        return Funcs.callback;
    }

    pub fn defineFunction(_: *const Scripting, onto: Value, name: []const u8, func: NativeCallback) void {
        pocketpy.py_bindfunc(onto, @ptrCast(name), func);
    }

    pub fn callFunction(_: *const Scripting, func: *const Function) void {
        pocketpy.py_push(func.value);
        pocketpy.py_pushnil();
        if (!pocketpy.py_vectorcall(0, 0)) {
            pocketpy.py_printexc();
        }
    }

    pub fn run(_: *const Scripting, src: []const u8, file: []const u8) !void {
        if (!pocketpy.py_exec(@ptrCast(src), @ptrCast(file), pocketpy.EXEC_MODE, null)) {
            pocketpy.py_printexc();
            return error.PythonError;
        }
    }
};
