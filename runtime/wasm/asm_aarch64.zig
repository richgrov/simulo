const Register = enum(u32) {
    lr = 30,
};

const Assembler = struct {
    memory: [*c]u32,
    write_index: usize = 0,

    pub fn init(memory: [*c]u32) Assembler {
        return Assembler{
            .memory = memory,
        };
    }

    pub fn ret_register(self: *Assembler, register: Register) void {
        const base = 0b11010110010111110000000000000000;
        self.memory[self.write_index] = base | (@intFromEnum(register) << 5);
        self.write_index += 1;
    }

    pub fn ret(self: *Assembler) void {
        self.ret_register(Register.lr);
    }
};

pub fn writeAssembly(target: *anyopaque) void {
    const assembly: [*c]u32 = @alignCast(@ptrCast(target));
    var assembler = Assembler.init(assembly);
    assembler.ret();
}
