const std = @import("std");

const reflect = @import("../util/util.zig").reflect;

const wasm = @cImport({
    @cInclude("wasm_c_api.h");
    @cInclude("wasm_export.h");
});

fn typeToSignature(T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .void => "",
        .int => |int| switch (int.bits) {
            32 => "i",
            64 => "I",
            else => @compileError(@typeName(T) ++ " not supported for wasm"),
        },
        .float => |float| switch (float.bits) {
            32 => "f",
            64 => "F",
            else => @compileError(@typeName(T) ++ " not supported for wasm"),
        },
        else => @compileError(@typeName(T) ++ " not supported for wasm"),
    };
}

fn createWasmSignature(func_info: std.builtin.Type.Fn) []const u8 {
    const fmt = "(" ++ "{s}" ** (func_info.params.len - 1) ++ "){s}";
    const Params = std.meta.Tuple(&[_]type{[]const u8} ** func_info.params.len);
    var params: Params = undefined;
    inline for (1..func_info.params.len) |i| {
        params[i - 1] = typeToSignature(func_info.params[i].type.?);
    }
    params[func_info.params.len - 1] = typeToSignature(func_info.return_type.?);
    return std.fmt.comptimePrint(fmt, params);
}

pub const Wasm = struct {
    module: wasm.wasm_module_t = null,
    module_instance: wasm.wasm_module_inst_t = null,
    exec_env: wasm.wasm_exec_env_t = null,

    pub const Function = wasm.wasm_function_inst_t;

    pub fn globalInit() !void {
        if (!wasm.wasm_runtime_init()) {
            return error.WasmRuntimeInitFailed;
        }
    }

    pub fn exposeFunction(comptime name: []const u8, func: anytype) !void {
        const func_info = switch (@typeInfo(@TypeOf(func))) {
            .@"fn" => |fi| fi,
            else => @compileError("must pass a function into exposeFunction"),
        };

        const ZigArgs = reflect.functionParamsIntoTuple(func_info.params);

        const Callback = struct {
            var native_symbol: wasm.NativeSymbol = .{
                .symbol = @ptrCast(name),
                .func_ptr = switch (func_info.params.len - 1) {
                    1 => @constCast(@ptrCast(&one_arg)),
                    2 => @constCast(@ptrCast(&two_args)),
                    3 => @constCast(@ptrCast(&three_args)),
                    else => @compileError("unsupported number of parameters"),
                },
                .signature = @ptrCast(createWasmSignature(func_info)),
            };

            pub fn one_arg(
                env: wasm.wasm_exec_env_t,
                arg1: func_info.params[1].type.?,
            ) callconv(.C) func_info.return_type.? {
                return @call(.auto, func, ZigArgs{
                    wasm.wasm_runtime_get_user_data(env).?,
                    arg1,
                });
            }

            pub fn two_args(
                env: wasm.wasm_exec_env_t,
                arg1: func_info.params[1].type.?,
                arg2: func_info.params[2].type.?,
            ) callconv(.C) func_info.return_type.? {
                return @call(.auto, func, ZigArgs{
                    wasm.wasm_runtime_get_user_data(env).?,
                    arg1,
                    arg2,
                });
            }

            pub fn three_args(
                env: wasm.wasm_exec_env_t,
                arg1: func_info.params[1].type.?,
                arg2: func_info.params[2].type.?,
                arg3: func_info.params[3].type.?,
            ) callconv(.C) func_info.return_type.? {
                return @call(.auto, func, ZigArgs{
                    wasm.wasm_runtime_get_user_data(env).?,
                    arg1,
                    arg2,
                    arg3,
                });
            }
        };

        if (!wasm.wasm_runtime_register_natives("env", &Callback.native_symbol, 1)) {
            return error.WasmRuntimeRegisterFailed;
        }
    }

    pub fn globalDeinit() void {
        wasm.wasm_runtime_destroy();
    }

    pub fn zeroInit(self: *Wasm) void {
        self.module = null;
        self.module_instance = null;
        self.exec_env = null;
    }

    pub fn init(self: *Wasm, user_data: *anyopaque, data: []const u8) !void {
        var error_buf: [1024 * 10]u8 = undefined;
        self.module = wasm.wasm_runtime_load(@constCast(data.ptr), @intCast(data.len), @ptrCast(&error_buf), error_buf.len) orelse return error.WasmLoadFailed;
        errdefer wasm.wasm_runtime_unload(self.module);
        self.module_instance = wasm.wasm_runtime_instantiate(self.module, 1024 * 8, 1024 * 64, @ptrCast(&error_buf), @intCast(error_buf.len)) orelse return error.WasmInstantiateFailed;
        errdefer wasm.wasm_runtime_deinstantiate(self.module_instance);
        self.exec_env = wasm.wasm_runtime_create_exec_env(self.module_instance, 1024 * 8) orelse return error.WasmExecEnvCreateFailed;
        wasm.wasm_runtime_set_user_data(self.exec_env, user_data);
    }

    pub fn deinit(self: *Wasm) void {
        if (self.exec_env) |exec_env| {
            wasm.wasm_runtime_destroy_exec_env(exec_env);
        }

        if (self.module_instance) |module_instance| {
            wasm.wasm_runtime_deinstantiate(module_instance);
        }

        if (self.module) |module| {
            wasm.wasm_runtime_unload(module);
        }
    }

    pub fn getFunction(self: *Wasm, name: []const u8) !Function {
        const func = wasm.wasm_runtime_lookup_function(self.module_instance, @ptrCast(name)) orelse return error.WasmFunctionLookupFailed;
        return func;
    }

    pub fn callFunction(self: *Wasm, func: Function, args: anytype) !u32 {
        var wasm_args: [@max(1, args.len)]u32 = undefined;
        inline for (args, 0..) |arg, i| {
            const Arg = @TypeOf(arg);
            if (Arg == u32) {
                wasm_args[i] = arg;
            } else if (Arg == i32) {
                wasm_args[i] = @intCast(arg);
            } else if (Arg == f32) {
                wasm_args[i] = @bitCast(arg);
            } else {
                @compileError("can't pass " ++ @typeName(Arg) ++ " to wasm function");
            }
        }

        if (!wasm.wasm_runtime_call_wasm(self.exec_env, func, @intCast(args.len), @ptrCast(&wasm_args))) {
            return error.WasmFunctionCallFailed;
        }
        return wasm_args[0];
    }
};
