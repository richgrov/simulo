const std = @import("std");

const reflect = @import("../util/util.zig").reflect;

const pocketpy = @cImport({
    @cInclude("vendor/pocketpy/pocketpy.h");
});

// https://github.com/ziglang/zig/issues/19858#issuecomment-2369861301
const TypeId = *const struct {
    _: u8,
};

pub inline fn typeId(comptime T: type) TypeId {
    return &struct {
        comptime {
            _ = T;
        }
        var id: @typeInfo(TypeId).pointer.child = undefined;
    }.id;
}

fn typeToPyType(T: type) ?c_int {
    if (T == Scripting.Function) {
        return pocketpy.tp_function;
    } else if (T == i64) {
        return pocketpy.tp_int;
    } else if (T == f64) {
        return pocketpy.tp_float;
    } else if (T == Scripting.Any) {
        return null;
    }

    @compileError(@typeName(T) ++ " cannot be converted into a Python type");
}

pub const Scripting = struct {
    pub const Value = *pocketpy.py_TValue;
    pub const Type = pocketpy.py_Type;
    pub const NativeCallback = pocketpy.py_CFunction;
    pub const Function = struct {
        value: *pocketpy.py_TValue,
    };
    pub const Any = struct {
        value: *pocketpy.py_TValue,
        ty: Type,
    };

    types: std.AutoHashMap(TypeId, pocketpy.py_Type),

    pub fn init(user_data: *anyopaque, allocator: std.mem.Allocator) Scripting {
        pocketpy.py_initialize();
        pocketpy.py_setvmctx(user_data);
        return .{
            .types = std.AutoHashMap(TypeId, pocketpy.py_Type).init(allocator),
        };
    }

    pub fn deinit(self: *Scripting) void {
        pocketpy.py_finalize();
        self.types.deinit();
    }

    pub fn defineModule(_: *const Scripting, name: []const u8) Value {
        return pocketpy.py_newmodule(@ptrCast(name)).?;
    }

    pub fn defineClass(self: *Scripting, T: type, module: Value) !Type {
        const struct_name = reflect.structName(T);
        const ty = pocketpy.py_newtype(@ptrCast(struct_name), pocketpy.tp_object, module, null);
        try self.types.put(typeId(T), ty);

        const Methods = struct {
            pub fn new(argc: c_int, argv: pocketpy.py_StackRef) callconv(.C) bool {
                _ = argc;

                const class = pocketpy.py_totype(argv);
                _ = pocketpy.py_newobject(pocketpy.py_retval(), class, -1, @sizeOf(T));
                return true;
            }
        };

        pocketpy.py_bindmethod(ty, "__new__", Methods.new);
        return ty;
    }

    pub fn defineFunction(self: *const Scripting, onto: Value, name: []const u8, func: anytype) void {
        const func_obj = self.createFunction(func);
        pocketpy.py_bindfunc(onto, @ptrCast(name), func_obj);
    }

    pub fn defineMethod(self: *const Scripting, onto: type, comptime name: []const u8, func: anytype) void {
        if (comptime std.mem.eql(u8, name, "__new__")) {
            @compileError("python structs already have a __new__ method");
        }

        const func_obj = self.createFunction(func);
        const py_type = self.types.get(typeId(onto)) orelse std.debug.panic("type must be defined before adding methods", .{});
        pocketpy.py_bindmethod(py_type, @ptrCast(name), func_obj);
    }

    pub fn defineProperty(self: *const Scripting, onto: type, comptime name: []const u8, getter: anytype) void {
        const py_type = self.types.get(typeId(onto)) orelse std.debug.panic("type must be defined before adding properties", .{});
        const getter_obj = self.createFunction(getter);
        pocketpy.py_bindproperty(py_type, @ptrCast(name), getter_obj, null);
    }

    fn createFunction(_: *const Scripting, func: anytype) NativeCallback {
        const func_info = switch (@typeInfo(@TypeOf(func))) {
            .@"fn" => |f| f,
            else => @compileError("non-function passed to createFunction"),
        };

        const params = func_info.params;
        if (params.len < 1) {
            @compileError("all native functions must accept at least one parameter for a context pointer");
        }

        const ret_type = func_info.return_type.?;

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
                    const type_id = comptime typeToPyType(params[i + 1].type.?);
                    if (type_id) |py_type| {
                        if (!pocketpy.py_checktype(pocketpy.py_offset(argv, i), @intCast(py_type))) {
                            return false;
                        }
                    }

                    const value = pocketpy.py_offset(argv, i).?;

                    if (type_id) |py_type| {
                        switch (py_type) {
                            pocketpy.tp_function => {
                                const name = pocketpy.py_name("todo");
                                pocketpy.py_setglobal(name, value);
                                const persistent_value = pocketpy.py_getglobal(name).?;
                                args[i + 1] = Function{ .value = persistent_value };
                            },
                            pocketpy.tp_int => {
                                args[i + 1] = pocketpy.py_toint(value);
                            },
                            pocketpy.tp_float => {
                                args[i + 1] = pocketpy.py_tofloat(value);
                            },
                            else => {
                                unreachable;
                            },
                        }
                    } else {
                        args[i + 1] = Any{
                            .value = value,
                            .ty = pocketpy.py_typeof(value),
                        };
                    }
                }

                const res = @call(.auto, func, args);
                if (ret_type == i64) {
                    pocketpy.py_newint(pocketpy.py_retval(), res);
                } else if (ret_type == f64) {
                    pocketpy.py_newfloat(pocketpy.py_retval(), res);
                } else if (ret_type == void) {
                    pocketpy.py_newnone(pocketpy.py_retval());
                } else {
                    @compileError("function return type " ++ @typeName(ret_type) ++ " not Python-compatible");
                }
                return true;
            }
        };
        return Funcs.callback;
    }

    pub fn callFunction(_: *const Scripting, func: *const Function, args: anytype) void {
        pocketpy.py_push(func.value);
        pocketpy.py_pushnil();

        inline for (0..args.len) |i| {
            const ty = @TypeOf(args[i]);
            if (ty == f64) {
                pocketpy.py_newfloat(pocketpy.py_pushtmp(), args[i]);
            } else if (ty == i64) {
                pocketpy.py_newint(pocketpy.py_pushtmp(), args[i]);
            } else {
                @compileError(@typeName(ty) ++ " not convertible to Python");
            }
        }

        if (!pocketpy.py_vectorcall(@intCast(args.len), 0)) {
            pocketpy.py_printexc();
        }
    }

    pub fn run(_: *const Scripting, src: []const u8, file: []const u8) !void {
        if (!pocketpy.py_exec(@ptrCast(src), @ptrCast(file), pocketpy.EXEC_MODE, null)) {
            pocketpy.py_printexc();
            return error.PythonError;
        }
    }

    pub fn getRawSelf(_: *const Scripting, any: Any) *anyopaque {
        return pocketpy.py_touserdata(any.value).?;
    }

    pub fn getSelf(self: *const Scripting, T: type, any: Scripting.Any) ?*T {
        const py_type = self.types.get(typeId(T)) orelse return null;
        if (any.ty != py_type) {
            return null;
        }

        const user_data = self.getRawSelf(any);
        return @alignCast(@ptrCast(user_data));
    }

    pub fn keepMemberAlive(_: *const Scripting, obj: Any, target: Any, name: []const u8) void {
        const key = pocketpy.py_name(@ptrCast(name));
        pocketpy.py_setdict(obj.value, key, target.value);
    }
};
