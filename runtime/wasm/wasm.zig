const std = @import("std");
const build_options = @import("build_options");
const Logger = @import("../log.zig").Logger;

const reflect = @import("util").reflect;

const wasm = @cImport({
    @cInclude("wasmtime.h");
});

const WasmErrorFormatter = struct {
    err: *wasm.wasmtime_error_t,

    pub fn format(self: WasmErrorFormatter, writer: anytype) !void {
        var buf: wasm.wasm_byte_vec_t = undefined;
        wasm.wasmtime_error_message(self.err, &buf);
        try writer.print("{s}", .{buf.data[0..buf.size]});
        defer wasm.wasm_byte_vec_delete(&buf);
    }
};

fn errFmt(err: *wasm.wasmtime_error_t) WasmErrorFormatter {
    return .{ .err = err };
}

pub const Wasm = struct {
    engine: *wasm.wasm_engine_t,
    linker: *wasm.wasmtime_linker_t,
    store: ?*wasm.wasmtime_store_t = null,
    context: ?*wasm.wasmtime_context_t = null,
    module: ?*wasm.wasmtime_module_t = null,
    module_instance: wasm.wasmtime_instance_t = undefined,
    memory: []u8 = undefined,
    logger: Logger("wasm", 2048),

    watchdog_thread: ?std.Thread = null,
    running: bool = false,

    pub const Function = wasm.wasmtime_func_t;

    pub fn exposeFunction(self: *Wasm, comptime name: []const u8, func: anytype) !void {
        const func_info = switch (@typeInfo(@TypeOf(func))) {
            .@"fn" => |fi| fi,
            else => @compileError("must pass a function into exposeFunction"),
        };

        var params: [func_info.params.len - 1]*wasm.wasm_valtype_t = undefined;
        inline for (0..(func_info.params.len - 1)) |i| {
            const param_type = func_info.params[i + 1].type.?;
            params[i] = switch (param_type) {
                u32, i32 => wasm.wasm_valtype_new_i32().?,
                u64, i64 => wasm.wasm_valtype_new_i64().?,
                f32 => wasm.wasm_valtype_new_f32().?,
                f64 => wasm.wasm_valtype_new_f64().?,
                else => switch (@typeInfo(param_type)) {
                    .pointer => wasm.wasm_valtype_new_i32().?,
                    else => {
                        @compileError(@typeName(func_info.params[i + 1].type.?) ++ " not supported for wasm parameter");
                    },
                },
            };
        }

        var param_vec: wasm.wasm_valtype_vec_t = undefined;
        wasm.wasm_valtype_vec_new(&param_vec, params.len, &params);
        defer wasm.wasm_valtype_vec_delete(&param_vec);

        const results = if (func_info.return_type.? == void) [_]*wasm.wasm_valtype_t{} else [_]*wasm.wasm_valtype_t{
            switch (func_info.return_type.?) {
                u32, i32, bool => wasm.wasm_valtype_new_i32().?,
                u64, i64 => wasm.wasm_valtype_new_i64().?,
                f32 => wasm.wasm_valtype_new_f32().?,
                f64 => wasm.wasm_valtype_new_f64().?,
                else => @compileError(@typeName(func_info.return_type.?) ++ " not supported for wasm return type"),
            },
        };

        var result_vec: wasm.wasm_valtype_vec_t = undefined;
        wasm.wasm_valtype_vec_new(&result_vec, results.len, &results);
        defer wasm.wasm_valtype_vec_delete(&result_vec);

        const func_type = wasm.wasm_functype_new(&param_vec, &result_vec);

        const Callback = struct {
            pub fn callback(
                env: ?*anyopaque,
                _: ?*wasm.wasmtime_caller_t,
                argv: [*c]const wasm.wasmtime_val_t,
                _: usize,
                resultv: [*c]wasm.wasmtime_val_t,
                _: usize,
            ) callconv(.c) ?*wasm.wasm_trap_t {
                const wasm_instance: *Wasm = @ptrCast(@alignCast(env));

                const Args = reflect.functionParamsIntoTuple(func_info.params[1..]);
                var args: Args = undefined;
                inline for (0..(func_info.params.len - 1)) |i| {
                    const param_type = func_info.params[i + 1].type.?;
                    args[i] = switch (param_type) {
                        u32, i32 => @bitCast(argv[i].of.i32),
                        u64, i64 => @bitCast(argv[i].of.i64),
                        f32 => argv[i].of.f32,
                        f64 => argv[i].of.f64,
                        else => switch (@typeInfo(param_type)) {
                            .pointer => @ptrCast(@alignCast(wasm_instance.memory.ptr + @as(u32, @bitCast(argv[i].of.i32)))),
                            else => {
                                @compileError(@typeName(func_info.params[i + 1].type.?) ++ " not supported for wasm parameter");
                            },
                        },
                    };
                }

                const result = @call(.auto, func, .{wasm_instance} ++ args);

                if (func_info.return_type.? != void) {
                    switch (func_info.return_type.?) {
                        bool => {
                            resultv.*.kind = wasm.WASMTIME_I32;
                            resultv.*.of.i32 = @intFromBool(result);
                        },
                        u32, i32 => {
                            resultv.*.kind = wasm.WASMTIME_I32;
                            resultv.*.of.i32 = @bitCast(result);
                        },
                        u64, i64 => {
                            resultv.*.kind = wasm.WASMTIME_I64;
                            resultv.*.of.i64 = @bitCast(result);
                        },
                        f32 => {
                            resultv.*.kind = wasm.WASMTIME_F32;
                            resultv.*.of.f32 = result;
                        },
                        f64 => {
                            resultv.*.kind = wasm.WASMTIME_F64;
                            resultv.*.of.f64 = result;
                        },
                        else => @compileError("unreachable: return type"),
                    }
                }

                return null;
            }
        };

        const module_name = "env";
        if (wasm.wasmtime_linker_define_func(
            self.linker,
            module_name.ptr,
            module_name.len,
            name.ptr,
            name.len,
            func_type,
            &Callback.callback,
            self,
            null,
        )) |err| {
            defer wasm.wasmtime_error_delete(err);
            self.logger.err("Failed to register wasm function: {f}", .{errFmt(err)});
            return error.WasmRuntimeRegisterFailed;
        }
    }

    pub fn init() !Wasm {
        var logger = Logger("wasm", 2048).init();

        const config = wasm.wasm_config_new() orelse return error.CreateWasmConfigFailed;
        wasm.wasmtime_config_epoch_interruption_set(config, true);

        const engine = wasm.wasm_engine_new_with_config(config) orelse return error.CreateWasmEngineFailed;
        errdefer wasm.wasm_engine_delete(engine);

        const linker = wasm.wasmtime_linker_new(engine).?;
        errdefer wasm.wasmtime_linker_delete(linker);

        if (wasm.wasmtime_linker_define_wasi(linker)) |err| {
            defer wasm.wasmtime_error_delete(err);
            logger.err("failed to define wasi in linker: {f}", .{errFmt(err)});
            return error.WasmDefineWasiFailed;
        }

        return .{
            .engine = engine,
            .linker = linker,
            .logger = logger,
        };
    }

    pub fn startWatchdog(self: *Wasm) !void {
        @atomicStore(bool, &self.running, true, .seq_cst);

        const Watchdog = struct {
            pub fn run(this: *Wasm) void {
                while (@atomicLoad(bool, &this.running, .seq_cst)) {
                    wasm.wasmtime_engine_increment_epoch(this.engine);
                    std.Thread.sleep(std.time.ns_per_s);
                }
            }
        };

        self.watchdog_thread = try std.Thread.spawn(
            .{},
            Watchdog.run,
            .{self},
        );
    }

    pub fn load(self: *Wasm, data: []const u8) !void {
        self.unload();

        var module: ?*wasm.wasmtime_module_t = undefined;
        if (wasm.wasmtime_module_new(self.engine, data.ptr, data.len, &module)) |err| {
            defer wasm.wasmtime_error_delete(err);
            self.logger.err("failed to create wasm module: {f}", .{errFmt(err)});
            return error.CreateWasmModuleFailed;
        }
        errdefer wasm.wasmtime_module_delete(module);

        const store = wasm.wasmtime_store_new(self.engine, null, null).?;
        errdefer wasm.wasmtime_store_delete(store);
        const context = wasm.wasmtime_store_context(store);

        const config = wasm.wasi_config_new();
        wasm.wasi_config_inherit_stdout(config);
        wasm.wasi_config_inherit_stderr(config);

        if (wasm.wasmtime_context_set_wasi(context, config)) |err| {
            defer wasm.wasmtime_error_delete(err);
            self.logger.err("failed to set wasi: {f}", .{errFmt(err)});
            return error.SetWasiFailed;
        }

        var module_instance: wasm.wasmtime_instance_t = undefined;
        var trap: ?*wasm.wasm_trap_t = null;
        if (wasm.wasmtime_linker_instantiate(self.linker, context, module, &module_instance, &trap)) |err| {
            defer wasm.wasmtime_error_delete(err);
            self.logger.err("failed to create wasm instance: {f}", .{errFmt(err)});
            return error.CreateWasmInstanceFailed;
        }

        if (trap != null) {
            var message: wasm.wasm_byte_vec_t = undefined;
            wasm.wasm_trap_message(trap, &message);
            self.logger.err("Trap on creating wasm instance: {s}", .{message.data[0..message.size]});
            wasm.wasm_byte_vec_delete(&message);
            return error.CreateWasmInstanceTrap;
        }

        var extern_memory: wasm.wasmtime_extern_t = undefined;
        const memory_name = "memory";
        if (!wasm.wasmtime_instance_export_get(context, &module_instance, memory_name.ptr, memory_name.len, &extern_memory)) {
            return error.WasmModuleHasNoMemory;
        }

        if (extern_memory.kind != wasm.WASMTIME_EXTERN_MEMORY) {
            return error.WasmModuleMemoryWrongType;
        }

        const mem_ptr = wasm.wasmtime_memory_data(context, &extern_memory.of.memory);
        const mem_size = wasm.wasmtime_memory_data_size(context, &extern_memory.of.memory);

        self.store = store;
        self.context = context;
        self.module = module;
        self.module_instance = module_instance;
        self.memory = mem_ptr[0..mem_size];
    }

    fn unload(self: *Wasm) void {
        if (self.store != null) {
            wasm.wasmtime_store_delete(self.store);
        }

        if (self.module != null) {
            wasm.wasmtime_module_delete(self.module);
            self.module = null;
        }
    }

    pub fn deinit(self: *Wasm) void {
        @atomicStore(bool, &self.running, false, .seq_cst);
        if (self.watchdog_thread) |*thread| {
            thread.join();
        }

        self.unload();

        wasm.wasmtime_linker_delete(self.linker);
        wasm.wasm_engine_delete(self.engine);
    }

    pub fn getFunction(self: *Wasm, name: []const u8) ?Function {
        var ref: wasm.wasmtime_extern_t = undefined;
        if (!wasm.wasmtime_instance_export_get(self.context, &self.module_instance, name.ptr, name.len, &ref)) {
            return null;
        }

        if (ref.kind != wasm.WASMTIME_EXTERN_FUNC) {
            return null;
        }

        return ref.of.func;
    }

    pub fn callFunction(self: *Wasm, func: Function, args: anytype) !void {
        var wasm_args: [args.len]wasm.wasmtime_val_t = undefined;
        inline for (args, 0..) |arg, i| {
            const Arg = @TypeOf(arg);
            switch (Arg) {
                i32, u32 => {
                    wasm_args[i].kind = wasm.WASMTIME_I32;
                    wasm_args[i].of.i32 = @bitCast(arg);
                },
                i64, u64 => {
                    wasm_args[i].kind = wasm.WASMTIME_I64;
                    wasm_args[i].of.i64 = @bitCast(arg);
                },
                f32 => {
                    wasm_args[i].kind = wasm.WASMTIME_F32;
                    wasm_args[i].of.f32 = @bitCast(arg);
                },
                f64 => {
                    wasm_args[i].kind = wasm.WASMTIME_F64;
                    wasm_args[i].of.f64 = @bitCast(arg);
                },
                bool => {
                    wasm_args[i].kind = wasm.WASMTIME_I32;
                    wasm_args[i].of.i32 = @intFromBool(arg);
                },
                else => @compileError("can't pass " ++ @typeName(Arg) ++ " to wasm function"),
            }
        }

        wasm.wasmtime_context_set_epoch_deadline(self.context, 2);

        var trap: ?*wasm.wasm_trap_t = null;
        if (wasm.wasmtime_func_call(self.context, &func, &wasm_args, args.len, null, 0, &trap)) |err| {
            defer wasm.wasmtime_error_delete(err);
            self.logger.err("Wasm function call failed: {f}", .{errFmt(err)});
            return error.WasmFunctionCallError;
        }

        if (trap != null) {
            var message: wasm.wasm_byte_vec_t = undefined;
            wasm.wasm_trap_message(trap, &message);
            self.logger.err("Wasm function call trap: {s}", .{message.data[0..message.size]});
            wasm.wasm_byte_vec_delete(&message);
            return error.WasmFunctionCallTrap;
        }
    }

    pub fn isNullptr(self: *Wasm, ptr: *anyopaque) bool {
        return @as(*u8, @ptrCast(ptr)) - self.memory.ptr == 0;
    }
};
