const std = @import("std");

const Error = @import("error.zig").Error;
const Module = @import("deserializer.zig").Module;

const Register = enum(u32) {
    x0,
    x1,
    x2,
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

const Assembler = struct {
    memory: [*c]u32,
    write_index: usize = 0,

    pub fn init(memory: [*c]u32) Assembler {
        return Assembler{
            .memory = memory,
        };
    }

    pub fn mov_reg_to_reg(self: *Assembler, src: Register, dst: Register) void {
        const base = 0b10101010000000000000001111100000;
        self.memory[self.write_index] = base | (@intFromEnum(src) << 16) | @intFromEnum(dst);
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

    pub fn brk(self: *Assembler) void {
        self.memory[self.write_index] = 0b11010100001000000000000000000000;
        self.write_index += 1;
    }

    pub fn push(self: *Assembler, register: Register) void {
        self.strRegisterPreIndex(register, -64, Register.sp);
    }

    pub fn pop(self: *Assembler, register: Register) void {
        self.ldrRegisterPostIndex(register, 64, Register.sp);
    }
};

pub fn writeAssembly(target: *anyopaque, module: *const Module) !?Error {
    for (0..module.functions.len) |i| {
        const code = &module.codes[i];
        const type_idx = module.functions[i];
        const function_type = module.types[type_idx];
        _ = function_type;

        for (code.instructions) |instruction| {
            switch (instruction) {
                else => {
                    return Error{ .invalid_instruction = instruction };
                },
            }
        }
    }

    const assembly: [*c]u32 = @alignCast(@ptrCast(target));
    var assembler = Assembler.init(assembly);

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
    return null;
}
