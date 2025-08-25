const std = @import("std");

const util = @import("util");

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

pub const Function = struct {
    offset: usize,
    ty: FunctionType,
};

pub const CompiledModule = struct {
    instructions: []u32,
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
            @compileError("getFunction: signature must be callconv(.C) but was " ++ @tagName(info.calling_convention));
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

        const first_instruction_addr = &self.instructions[function.offset];
        const func: *const signature = @alignCast(@ptrCast(first_instruction_addr));
        return func;
    }
};

const Assembler = struct {
    memory: *std.ArrayList(u32),

    pub fn wrap(buffer: *std.ArrayList(u32)) Assembler {
        return Assembler{
            .memory = buffer,
        };
    }

    pub fn mov_reg_to_reg(self: *Assembler, src: Register, dst: Register) !void {
        const base = 0b10101010000000000000001111100000;
        try self.memory.append(base | (@intFromEnum(src) << 16) | @intFromEnum(dst));
    }

    pub fn mov_imm_to_reg(self: *Assembler, value: i32, dst: Register) !void {
        const base = 0b11010010100000000000000000000000;
        const value_u: u32 = @bitCast(value);
        try self.memory.append(base | (value_u << 5) | (@intFromEnum(dst) << 0));
    }

    pub fn add_reg_to_reg(self: *Assembler, src_a: Register, src_b: Register, dst: Register) !void {
        const base = 0b00001011001000000000000000000000;
        try self.memory.append(base | (@intFromEnum(src_a) << 16) | (@intFromEnum(src_b) << 5) | @intFromEnum(dst));
    }

    pub fn sub_reg_to_reg(self: *Assembler, src_a: Register, src_b: Register, dst: Register) !void {
        const base = 0b11101011000000000000000000000000;
        try self.memory.append(base | (@intFromEnum(src_b) << 16) | (@intFromEnum(src_a) << 5) | @intFromEnum(dst));
    }

    pub fn mul_reg_to_reg(self: *Assembler, src_a: Register, src_b: Register, dst: Register) !void {
        const base = 0b10011011000000000111110000000000;
        try self.memory.append(base | (@intFromEnum(src_a) << 16) | (@intFromEnum(src_b) << 5) | @intFromEnum(dst));
    }

    pub fn sdiv_reg_to_reg(self: *Assembler, src_a: Register, src_b: Register, dst: Register) !void {
        const base = 0b10011010110000000000110000000000;
        try self.memory.append(base | (@intFromEnum(src_b) << 16) | (@intFromEnum(src_a) << 5) | @intFromEnum(dst));
    }

    pub fn udiv_reg_to_reg(self: *Assembler, src_a: Register, src_b: Register, dst: Register) !void {
        const base = 0b10011010110000000000100000000000;
        try self.memory.append(base | (@intFromEnum(src_b) << 16) | (@intFromEnum(src_a) << 5) | @intFromEnum(dst));
    }

    pub fn and_reg_to_reg(self: *Assembler, src_a: Register, src_b: Register, dst: Register) !void {
        const base = 0b10001010000000000000000000000000;
        try self.memory.append(base | (@intFromEnum(src_a) << 16) | (@intFromEnum(src_b) << 5) | @intFromEnum(dst));
    }

    pub fn sub_imm32(self: *Assembler, src: Register, dest: Register, imm: u12) !void {
        const base = 0b01010001000000000000000000000000;
        try self.memory.append(base | (@as(u32, @intCast(imm)) << 10) | (@intFromEnum(src) << 5) | @intFromEnum(dest));
    }

    pub fn cmp_reg_to_imm32(self: *Assembler, src: Register, imm: u12) !void {
        const base = 0b11110001000000000000000000011111;
        try self.memory.append(base | (@as(u32, @intCast(imm)) << 10) | (@intFromEnum(src) << 5));
    }

    pub fn cmp_reg_to_reg(self: *Assembler, src_a: Register, src_b: Register) !void {
        const base = 0b11101011000000000000000000011111;
        try self.memory.append(base | (@intFromEnum(src_a) << 16) | (@intFromEnum(src_b) << 5));
    }

    pub fn b(self: *Assembler, offset: i26) !void {
        const offset_u: u26 = @bitCast(offset);
        const base = 0b00010100000000000000000000000000;
        try self.memory.append(base | @as(u32, @intCast(offset_u)));
    }

    pub fn b_cond(self: *Assembler, cond: Condition, offset: i19) !void {
        const base = 0b01010100000000000000000000000000;
        try self.memory.append(base | (@as(u32, @intCast(offset)) << 5) | (@intFromEnum(cond) << 0));
    }

    pub fn bl_reg(self: *Assembler, register: Register) !void {
        const base = 0b11010110001111110000000000000000;
        try self.memory.append(base | (@intFromEnum(register) << 5));
    }

    pub fn ret_register(self: *Assembler, register: Register) !void {
        const base = 0b11010110010111110000000000000000;
        try self.memory.append(base | (@intFromEnum(register) << 5));
    }

    pub fn ret(self: *Assembler) !void {
        try self.ret_register(Register.lr);
    }

    pub fn strRegisterPreIndex(self: *Assembler, source: Register, offset: i9, into: Register) !void {
        const base = 0b11111000000000000000110000000000;
        const offsetU: u9 = @bitCast(offset);
        const offset32: u32 = @intCast(offsetU);
        try self.memory.append(base | (offset32 << 12) | (@intFromEnum(into) << 5) | (@intFromEnum(source) << 0));
    }

    pub fn ldrRegisterPostIndex(self: *Assembler, dest: Register, offset: i9, from: Register) !void {
        const base = 0b11111000010000000000010000000000;
        const offsetU: u9 = @bitCast(offset);
        const offset32: u32 = @intCast(offsetU);
        try self.memory.append(base | (offset32 << 12) | (@intFromEnum(from) << 5) | (@intFromEnum(dest) << 0));
    }

    pub fn ldrUnsignedOffset(self: *Assembler, dest: Register, offset: i12, from: Register) !void {
        const base = 0b11111001010000000000000000000000;
        const offsetU: u12 = @bitCast(offset);
        const offset32: u32 = @intCast(offsetU);
        try self.memory.append(base | (offset32 << 10) | (@intFromEnum(from) << 5) | (@intFromEnum(dest) << 0));
    }

    pub fn brk(self: *Assembler) !void {
        try self.memory.append(0b11010100001000000000000000000000);
    }

    pub fn push(self: *Assembler, register: Register) !void {
        try self.strRegisterPreIndex(register, -16, Register.sp);
    }

    pub fn pop(self: *Assembler, register: Register) !void {
        try self.ldrRegisterPostIndex(register, 16, Register.sp);
    }
};

fn compile(cpu_instructions: *std.ArrayList(u32), wasm_instructions: []const deserializer.Instruction, current_stack_depth: isize) !void {
    var assembler = Assembler.wrap(cpu_instructions);
    var stack_depth = current_stack_depth;
    var last_condition: ?Condition = null;

    var i: usize = 0;
    while (i < wasm_instructions.len) : (i += 1) {
        const instruction = wasm_instructions[i];

        switch (instruction) {
            .Unreachable => {},
            .If => |instr| {
                var true_asm = try std.ArrayList(u32).initCapacity(cpu_instructions.allocator, 16);
                try compile(&true_asm, instr.when_true, stack_depth);

                const false_asm = if (instr.when_false) |false_wasm_instructions| blk: {
                    var false_instructions = try std.ArrayList(u32).initCapacity(cpu_instructions.allocator, 16);
                    try compile(&false_instructions, false_wasm_instructions, stack_depth);

                    var true_assembler = Assembler.wrap(&true_asm);
                    try true_assembler.b(@intCast(false_instructions.items.len));

                    break :blk false_instructions;
                } else null;

                try assembler.b_cond(.ne, @intCast(true_asm.items.len + 1));
                try cpu_instructions.appendSlice(true_asm.items);

                if (false_asm) |false_asm_list| {
                    try cpu_instructions.appendSlice(false_asm_list.items);
                }
            },
            .LocalGet => |local_get| {
                const index: isize = @intCast(local_get.local_index);
                const depth: isize = @intCast(stack_depth);
                const stack_offset = (depth - index - 1) * (16 / 8); // divide by 8 for arm unsigned offset scaling
                try assembler.ldrUnsignedOffset(Register.x0, @intCast(stack_offset), Register.sp);
                try assembler.push(Register.x0);
                stack_depth += 1;
            },
            .I32Const => |value| {
                try assembler.mov_imm_to_reg(value, Register.x0);
                try assembler.push(Register.x0);
                stack_depth += 1;
            },
            .I32Eq => {
                try assembler.pop(Register.x2);
                try assembler.pop(Register.x1);
                try assembler.cmp_reg_to_reg(Register.x1, Register.x2);
                last_condition = Condition.eq;
            },
            .I32Add => {
                try assembler.pop(Register.x2);
                try assembler.pop(Register.x1);
                try assembler.add_reg_to_reg(Register.x1, Register.x2, Register.x0);
                try assembler.push(Register.x0);
                stack_depth -= 1;
            },
            .I32Sub => {
                try assembler.pop(Register.x2);
                try assembler.pop(Register.x1);
                try assembler.sub_reg_to_reg(Register.x1, Register.x2, Register.x0);
                try assembler.push(Register.x0);
                stack_depth -= 1;
            },
            .I32Mul => {
                try assembler.pop(Register.x2);
                try assembler.pop(Register.x1);
                try assembler.mul_reg_to_reg(Register.x1, Register.x2, Register.x0);
                try assembler.push(Register.x0);
                stack_depth -= 1;
            },
            .I32DivS => {
                try assembler.pop(Register.x2);
                try assembler.pop(Register.x1);
                try assembler.div_reg_to_reg(Register.x1, Register.x2, Register.x0);
                try assembler.push(Register.x0);
                stack_depth -= 1;
            },
            .I32DivU => {
                try assembler.pop(Register.x2);
                try assembler.pop(Register.x1);
                try assembler.div_reg_to_reg(Register.x1, Register.x2, Register.x0);
                try assembler.push(Register.x0);
                stack_depth -= 1;
            },
            .I32And => {
                try assembler.pop(Register.x2);
                try assembler.pop(Register.x1);
                try assembler.and_reg_to_reg(Register.x1, Register.x2, Register.x0);
                try assembler.push(Register.x0);
                stack_depth -= 1;
            },
            .Return => {
                try assembler.pop(Register.x0);
                stack_depth -= 1;

                while (stack_depth > 0) {
                    try assembler.pop(Register.x1);
                    stack_depth -= 1;
                }
                try assembler.ret();
            },
            else => return error.InvalidInstruction,
        }
    }
}

pub fn writeAssembly(out_buf: []u8, module: *const Module, allocator: std.mem.Allocator) !CompiledModule {
    const target_ptr: [*c]u32 = @alignCast(@ptrCast(out_buf.ptr));
    const target: []u32 = target_ptr[0 .. out_buf.len / @sizeOf(u32)];

    var exported_functions = std.StringHashMap(Function).init(allocator);
    errdefer exported_functions.deinit();

    var functions = std.ArrayList(Function).init(allocator);
    defer functions.deinit();
    functions.resize(module.functions.len) catch |err| util.crash.oom(err);

    var write_index: usize = 0;

    for (0..module.functions.len) |i| {
        const code = &module.codes[i];
        const type_idx = module.functions[i];
        const function_type = module.types[type_idx];

        var asm_instructions = try std.ArrayList(u32).initCapacity(allocator, 16);
        defer asm_instructions.deinit();

        var assembler = Assembler.wrap(&asm_instructions);

        const n_params = function_type.params.len;
        if (n_params > 0) try assembler.push(Register.x0);
        if (n_params > 1) try assembler.push(Register.x1);
        if (n_params > 2) try assembler.push(Register.x2);
        if (n_params > 3) try assembler.push(Register.x3);
        if (n_params > 4) try assembler.push(Register.x4);
        if (n_params > 5) try assembler.push(Register.x5);
        if (n_params > 6) try assembler.push(Register.x6);
        if (n_params > 7) try assembler.push(Register.x7);

        try compile(&asm_instructions, code.instructions, @intCast(n_params));

        functions.items[i] = .{
            .offset = write_index,
            .ty = function_type,
        };

        for (asm_instructions.items) |instruction| {
            target[write_index] = instruction;
            write_index += 1;
        }
    }

    for (module.exports) |exp| {
        if (exp.kind != .function) {
            return error.InvalidExportType;
        }

        const function = functions.items[exp.index];
        exported_functions.put(exp.name, function) catch |err| util.crash.oom(err);
    }

    return CompiledModule{
        .instructions = target,
        .functions = exported_functions,
    };
}
