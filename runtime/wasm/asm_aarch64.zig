const std = @import("std");

const util = @import("util");

const Error = @import("error.zig").Error;
const deserializer = @import("deserializer.zig");
const Module = deserializer.Module;
const FunctionType = deserializer.FunctionType;
const ValueType = deserializer.ValueType;

const Register = enum(u32) {
    x0,
    x1,
    x2,
    x3,
    x4,
    x5,
    x6,
    x7,
    lr = 30,
    sp = 31,
};

const Condition = enum(u32) {
    eq,
    ne,
    cs,
    cc,
    mi,
    pl,
    vs,
    vc,
    hi,
    ls,
    ge,
    lt,
    gt,
    le,
    al,
    nv,
};

pub const CompileResult = union(enum) {
    ok: CompiledModule,
    err: Error,
};

pub const Function = struct {
    offset: usize,
    ty: FunctionType,
};

pub const CompiledModule = struct {
    instructions: *anyopaque,
    functions: std.StringHashMap(Function),

    pub fn deinit(self: *CompiledModule) void {
        self.functions.deinit();
    }

    pub fn getFunction(self: *const CompiledModule, name: []const u8, signature: type) !?*const signature {
        const info = switch (@typeInfo(signature)) {
            .@"fn" => |fn_info| fn_info,
            else => @compileError("getFunction: fn type required"),
        };

        if (!info.calling_convention.eql(std.builtin.CallingConvention.c) and false) { // temporarily disabled due to bug in zig reflection
            @compileError("getFunction: signature must be callconv(.c) but was " ++ @tagName(info.calling_convention));
        }

        const function = self.functions.get(name) orelse return null;
        if (function.ty.results.len != 1) {
            return error.FunctionMultipleReturnValues;
        }

        if (function.ty.results[0] != ValueType.from(info.return_type.?)) {
            return error.FunctionReturnTypeMismatch;
        }

        if (info.params.len != function.ty.params.len) {
            return error.FunctionParamCountMismatch;
        }

        inline for (info.params, 0..) |param, i| {
            if (function.ty.params[i] != ValueType.from(param.type.?)) {
                return error.FunctionParamTypeMismatch;
            }
        }

        const buffer: [*c]u8 = @ptrCast(self.instructions);
        const func: *const signature = @ptrCast(@alignCast(&buffer[function.offset]));
        return func;
    }
};

const Assembler = struct {
    memory: [*c]u32,
    write_index: usize = 0,

    pub fn init(memory: [*c]u32) Assembler {
        return Assembler{
            .memory = memory,
        };
    }

    pub fn byteWriteIndex(self: *Assembler) usize {
        return self.write_index * @sizeOf(u32);
    }

    pub fn mov_reg_to_reg(self: *Assembler, src: Register, dst: Register) void {
        const base = 0b10101010000000000000001111100000;
        self.memory[self.write_index] = base | (@intFromEnum(src) << 16) | @intFromEnum(dst);
        self.write_index += 1;
    }

    pub fn mov_imm_to_reg(self: *Assembler, value: i32, dst: Register) void {
        const base = 0b11010010100000000000000000000000;
        const value_u: u32 = @bitCast(value);
        self.memory[self.write_index] = base | (value_u << 5) | (@intFromEnum(dst) << 0);
        self.write_index += 1;
    }

    pub fn add_reg_to_reg(self: *Assembler, src_a: Register, src_b: Register, dst: Register) void {
        const base = 0b00001011001000000000000000000000;
        self.memory[self.write_index] = base | (@intFromEnum(src_a) << 16) | (@intFromEnum(src_b) << 5) | @intFromEnum(dst);
        self.write_index += 1;
    }

    pub fn sub_imm32(self: *Assembler, src: Register, dest: Register, imm: u12) void {
        const base = 0b01010001000000000000000000000000;
        self.memory[self.write_index] = base | (@as(u32, @intCast(imm)) << 10) | (@intFromEnum(src) << 5) | @intFromEnum(dest);
        self.write_index += 1;
    }

    pub fn cmp_reg_to_imm32(self: *Assembler, src: Register, imm: u12) void {
        const base = 0b11110001000000000000000000011111;
        self.memory[self.write_index] = base | (@as(u32, @intCast(imm)) << 10) | (@intFromEnum(src) << 5);
        self.write_index += 1;
    }

    pub fn cmp_reg_to_reg(self: *Assembler, src_a: Register, src_b: Register) void {
        const base = 0b11101011000000000000000000011111;
        self.memory[self.write_index] = base | (@intFromEnum(src_a) << 16) | (@intFromEnum(src_b) << 5);
        self.write_index += 1;
    }

    pub fn b(self: *Assembler, offset: i26) void {
        const offset_u: u26 = @bitCast(offset);
        const base = 0b00010100000000000000000000000000;
        self.memory[self.write_index] = base | @as(u32, @intCast(offset_u));
        self.write_index += 1;
    }

    pub fn b_cond(self: *Assembler, cond: Condition, offset: i19) void {
        const base = 0b01010100000000000000000000000000;
        self.memory[self.write_index] = base | (@as(u32, @intCast(offset)) << 5) | (@intFromEnum(cond) << 0);
        self.write_index += 1;
    }

    pub fn bl_reg(self: *Assembler, register: Register) void {
        const base = 0b11010110001111110000000000000000;
        self.memory[self.write_index] = base | (@intFromEnum(register) << 5);
        self.write_index += 1;
    }

    pub fn ret_register(self: *Assembler, register: Register) void {
        const base = 0b11010110010111110000000000000000;
        self.memory[self.write_index] = base | (@intFromEnum(register) << 5);
        self.write_index += 1;
    }

    pub fn ret(self: *Assembler) void {
        self.ret_register(Register.lr);
    }

    pub fn strRegisterPreIndex(self: *Assembler, source: Register, offset: i9, into: Register) void {
        const base = 0b11111000000000000000110000000000;
        const offsetU: u9 = @bitCast(offset);
        const offset32: u32 = @intCast(offsetU);
        self.memory[self.write_index] = base | (offset32 << 12) | (@intFromEnum(into) << 5) | (@intFromEnum(source) << 0);
        self.write_index += 1;
    }

    pub fn ldrRegisterPostIndex(self: *Assembler, dest: Register, offset: i9, from: Register) void {
        const base = 0b11111000010000000000010000000000;
        const offsetU: u9 = @bitCast(offset);
        const offset32: u32 = @intCast(offsetU);
        self.memory[self.write_index] = base | (offset32 << 12) | (@intFromEnum(from) << 5) | (@intFromEnum(dest) << 0);
        self.write_index += 1;
    }

    pub fn ldrUnsignedOffset(self: *Assembler, dest: Register, offset: i12, from: Register) void {
        const base = 0b11111001010000000000000000000000;
        const offsetU: u12 = @bitCast(offset);
        const offset32: u32 = @intCast(offsetU);
        self.memory[self.write_index] = base | (offset32 << 10) | (@intFromEnum(from) << 5) | (@intFromEnum(dest) << 0);
        self.write_index += 1;
    }

    pub fn brk(self: *Assembler) void {
        self.memory[self.write_index] = 0b11010100001000000000000000000000;
        self.write_index += 1;
    }

    pub fn push(self: *Assembler, register: Register) void {
        self.strRegisterPreIndex(register, -16, Register.sp);
    }

    pub fn pop(self: *Assembler, register: Register) void {
        self.ldrRegisterPostIndex(register, 16, Register.sp);
    }
};

pub fn writeAssembly(target: *anyopaque, module: *const Module, allocator: std.mem.Allocator) CompileResult {
    const assembly: [*c]u32 = @ptrCast(@alignCast(target));
    var assembler = Assembler.init(assembly);
    var exported_functions = std.StringHashMap(Function).init(allocator);
    errdefer exported_functions.deinit();

    var functions = std.ArrayList(Function).init(allocator);
    defer functions.deinit();
    functions.resize(module.functions.len) catch |err| util.crash.oom(err);

    for (0..module.functions.len) |i| {
        const code = &module.codes[i];
        const type_idx = module.functions[i];
        const function_type = module.types[type_idx];

        functions.items[i] = .{
            .offset = assembler.byteWriteIndex(),
            .ty = function_type,
        };

        const n_params = function_type.params.len;
        var stack_depth = n_params;
        if (n_params > 0) assembler.push(Register.x0);
        if (n_params > 1) assembler.push(Register.x1);
        if (n_params > 2) assembler.push(Register.x2);
        if (n_params > 3) assembler.push(Register.x3);
        if (n_params > 4) assembler.push(Register.x4);
        if (n_params > 5) assembler.push(Register.x5);
        if (n_params > 6) assembler.push(Register.x6);
        if (n_params > 7) assembler.push(Register.x7);

        for (code.instructions) |instruction| {
            switch (instruction) {
                .LocalGet => |local_get| {
                    const index: isize = @intCast(local_get.local_index);
                    const depth: isize = @intCast(stack_depth);
                    const stack_offset = (depth - index - 1) * (16 / 8); // divide by 8 for arm unsigned offset scaling
                    assembler.ldrUnsignedOffset(Register.x0, @intCast(stack_offset), Register.sp);
                    assembler.push(Register.x0);
                    stack_depth += 1;
                },
                .I32Add => {
                    assembler.pop(Register.x2);
                    assembler.pop(Register.x1);
                    assembler.add_reg_to_reg(Register.x1, Register.x2, Register.x0);
                    assembler.push(Register.x0);
                    stack_depth -= 1;
                },
                .Return => {
                    assembler.pop(Register.x0);
                    stack_depth -= 1;

                    while (stack_depth > 0) {
                        assembler.pop(Register.x1);
                        stack_depth -= 1;
                    }
                    assembler.ret();
                },
                else => {
                    std.debug.print("Invalid instruction: {}\n", .{instruction});
                    return CompileResult{ .err = Error{ .invalid_instruction = instruction } };
                },
            }
        }
    }

    for (module.exports) |exp| {
        if (exp.kind != .function) {
            return CompileResult{ .err = Error{ .invalid_export_type = exp.kind } };
        }

        const function = functions.items[exp.index];
        exported_functions.put(exp.name, function) catch |err| util.crash.oom(err);
    }

    assembler.cmp_reg_to_imm32(Register.x1, 0);
    assembler.b_cond(Condition.eq, 12);

    assembler.push(Register.lr);
    assembler.push(Register.x0);
    assembler.push(Register.x1);
    assembler.mov_reg_to_reg(Register.x0, Register.x2);
    assembler.mov_reg_to_reg(Register.x1, Register.x0);
    assembler.bl_reg(Register.x2);
    assembler.pop(Register.x1);
    assembler.pop(Register.x0);
    assembler.pop(Register.lr);
    assembler.sub_imm32(Register.x1, Register.x1, 1);
    assembler.b(-12);

    assembler.mov_reg_to_reg(Register.x1, Register.x0);
    assembler.ret();

    return CompileResult{ .ok = CompiledModule{
        .instructions = target,
        .functions = exported_functions,
    } };
}
