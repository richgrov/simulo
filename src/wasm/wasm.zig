const std = @import("std");

const wasm = @cImport({
    @cInclude("wasm_c_api.h");
    @cInclude("wasm_export.h");
});

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

    pub fn globalDeinit() void {
        wasm.wasm_runtime_destroy();
    }

    pub fn zeroInit(self: *Wasm) void {
        self.module = null;
        self.module_instance = null;
        self.exec_env = null;
    }

    pub fn init(self: *Wasm, data: []const u8) !void {
        var error_buf: [1024 * 10]u8 = undefined;
        self.module = wasm.wasm_runtime_load(@constCast(data.ptr), @intCast(data.len), @ptrCast(&error_buf), error_buf.len) orelse return error.WasmLoadFailed;
        errdefer wasm.wasm_runtime_unload(self.module);
        self.module_instance = wasm.wasm_runtime_instantiate(self.module, 1024 * 8, 1024 * 64, @ptrCast(&error_buf), @intCast(error_buf.len)) orelse return error.WasmInstantiateFailed;
        errdefer wasm.wasm_runtime_deinstantiate(self.module_instance);
        self.exec_env = wasm.wasm_runtime_create_exec_env(self.module_instance, 1024 * 8) orelse return error.WasmExecEnvCreateFailed;
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

    pub fn callFunction(self: *Wasm, func: Function, args: []u32) !u32 {
        if (!wasm.wasm_runtime_call_wasm(self.exec_env, func, @intCast(args.len), @ptrCast(args))) {
            return error.WasmFunctionCallFailed;
        }
        return args[0];
    }
};
