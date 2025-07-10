const Instruction = @import("deserializer.zig").Instruction;

pub const Error = union(enum) {
    invalid_instruction: Instruction,
};
