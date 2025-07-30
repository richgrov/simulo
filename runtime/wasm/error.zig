const Instruction = @import("deserializer.zig").Instruction;
const ExportType = @import("deserializer.zig").ExportType;

pub const Error = union(enum) {
    invalid_instruction: Instruction,
    invalid_export_type: ExportType,
};
