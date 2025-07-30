const std = @import("std");

pub const ValueType = enum(i8) {
    i32 = 0x7f,
    i64 = 0x7e,
    f32 = 0x7d,
    f64 = 0x7c,

    pub fn from(ty: type) ValueType {
        return switch (ty) {
            i32 => .i32,
            i64 => .i64,
            f32 => .f32,
            f64 => .f64,
            else => @compileError("unsupported value type"),
        };
    }
};

pub const Local = struct {
    count: u32,
    value_type: ValueType,
};

pub const FunctionType = struct {
    params: []ValueType,
    results: []ValueType,
};

pub const Instruction = union(enum) {
    pub const MemArg = struct {
        alignment: u32,
        offset: u32,
    };

    Block: struct { block_type: i32 },
    Loop: struct { block_type: i32 },
    If: struct { block_type: i32 },
    Br: struct { label_index: u32 },
    BrIf: struct { label_index: u32 },
    BrTable: struct { targets: []u32, default_target: u32 },
    Return: void,
    Call: struct { func_index: u32 },
    CallIndirect: struct { type_index: u32, table_index: u32 },
    LocalGet: struct { local_index: u32 },
    LocalSet: struct { local_index: u32 },
    LocalTee: struct { local_index: u32 },
    GlobalGet: struct { global_index: u32 },
    GlobalSet: struct { global_index: u32 },
    I32Load: MemArg,
    I64Load: MemArg,
    F32Load: MemArg,
    F64Load: MemArg,
    I32Load8S: MemArg,
    I32Load8U: MemArg,
    I32Load16S: MemArg,
    I32Load16U: MemArg,
    I64Load8S: MemArg,
    I64Load8U: MemArg,
    I64Load16S: MemArg,
    I64Load16U: MemArg,
    I64Load32S: MemArg,
    I64Load32U: MemArg,
    I32Store: MemArg,
    I64Store: MemArg,
    F32Store: MemArg,
    F64Store: MemArg,
    I32Store8: MemArg,
    I32Store16: MemArg,
    I64Store8: MemArg,
    I64Store16: MemArg,
    I64Store32: MemArg,
    MemorySize: u32,
    MemoryGrow: u32,
    I32Const: i32,
    I64Const: i64,
    F32Const: f32,
    F64Const: f64,
    I32Add: void,
    Misc: struct { opcode: u8, bytes: []const u8 },
    Plain: u8,
};

pub const ExportType = enum(u8) {
    function = 0x00,
    table = 0x01,
    memory = 0x02,
    global = 0x03,
};

pub const Export = struct {
    name: []const u8,
    kind: ExportType,
    index: u32,
};

pub const Code = struct {
    locals: []Local,
    body: []const u8,
    instructions: []Instruction,
};

pub const Module = struct {
    types: []FunctionType,
    functions: []u32,
    codes: []Code,
    exports: []Export,

    pub fn deinit(self: *Module, allocator: std.mem.Allocator) void {
        for (self.types) |*t| {
            allocator.free(t.params);
            allocator.free(t.results);
        }
        allocator.free(self.types);
        allocator.free(self.functions);
        for (self.codes) |*c| {
            allocator.free(c.locals);
            freeInstructions(allocator, c.instructions);
        }
        allocator.free(self.codes);
        for (self.exports) |*e| {
            allocator.free(e.name);
        }
        allocator.free(self.exports);
    }
};

const Deserializer = struct {
    data: []const u8,
    index: usize = 0,
    allocator: std.mem.Allocator,

    fn readByte(self: *Deserializer) !u8 {
        if (self.index >= self.data.len) return error.UnexpectedEof;
        const b = self.data[self.index];
        self.index += 1;
        return b;
    }

    fn readSlice(self: *Deserializer, len: usize) ![]const u8 {
        if (self.index + len > self.data.len) return error.UnexpectedEof;
        const slice = self.data[self.index .. self.index + len];
        self.index += len;
        return slice;
    }

    fn readVarUint32(self: *Deserializer) !u32 {
        var result: u32 = 0;
        var shift: u32 = 0;
        while (true) {
            const byte = try self.readByte();
            result |= (@as(u32, byte & 0x7f)) << @as(u5, @intCast(shift));
            if (byte & 0x80 == 0) break;
            shift += 7;
        }
        return result;
    }

    fn readVarInt32(self: *Deserializer) !i32 {
        var result: i32 = 0;
        var shift: u32 = 0;
        var byte: u8 = 0;
        while (true) {
            byte = try self.readByte();
            result |= (@as(i32, @as(i8, @bitCast(byte & 0x7f)))) << @as(u5, @intCast(shift));
            shift += 7;
            if (byte & 0x80 == 0) break;
        }
        if (shift < 32 and (byte & 0x40) != 0) {
            result |= ~(@as(i32, 0)) << @as(u5, @intCast(shift));
        }
        return result;
    }

    fn readVarInt64(self: *Deserializer) !i64 {
        var result: i64 = 0;
        var shift: u32 = 0;
        var byte: u8 = 0;
        while (true) {
            byte = try self.readByte();
            result |= (@as(i64, @as(i8, @bitCast(byte & 0x7f)))) << @as(u6, @intCast(shift));
            shift += 7;
            if (byte & 0x80 == 0) break;
        }
        if (shift < 64 and (byte & 0x40) != 0) {
            result |= ~(@as(i64, 0)) << @as(u6, @intCast(shift));
        }
        return result;
    }
};

fn valueTypeFromByte(b: u8) !ValueType {
    return switch (b) {
        0x7f => .i32,
        0x7e => .i64,
        0x7d => .f32,
        0x7c => .f64,
        else => error.UnsupportedValueType,
    };
}

pub fn parseModule(allocator: std.mem.Allocator, data: []const u8) !Module {
    var d = Deserializer{ .data = data, .allocator = allocator };

    const magic = try d.readSlice(4);
    if (!std.mem.eql(u8, magic, "\x00asm")) return error.InvalidMagic;
    const version = try d.readSlice(4);
    if (!std.mem.eql(u8, version, "\x01\x00\x00\x00")) return error.UnsupportedVersion;

    var types = std.ArrayList(FunctionType).init(allocator);
    errdefer {
        for (types.items) |ty| {
            allocator.free(ty.params);
            allocator.free(ty.results);
        }
        types.deinit();
    }
    var functions = std.ArrayList(u32).init(allocator);
    errdefer functions.deinit();
    var codes = std.ArrayList(Code).init(allocator);
    errdefer {
        for (codes.items) |code| {
            allocator.free(code.locals);
            freeInstructions(allocator, code.instructions);
        }
        codes.deinit();
    }
    var exports = std.ArrayList(Export).init(allocator);
    errdefer {
        for (exports.items) |exp| {
            allocator.free(exp.name);
        }
        exports.deinit();
    }

    while (d.index < d.data.len) {
        const id = try d.readByte();
        const section_len = try d.readVarUint32();
        const end_index = d.index + section_len;
        switch (id) {
            1 => { // Type section
                const count = try d.readVarUint32();
                for (0..count) |_| {
                    const form = try d.readByte();
                    if (form != 0x60) return error.UnsupportedTypeForm;
                    const param_count = try d.readVarUint32();
                    const params = try allocator.alloc(ValueType, param_count);
                    errdefer allocator.free(params);
                    for (params) |*p| {
                        p.* = try valueTypeFromByte(try d.readByte());
                    }
                    const result_count = try d.readVarUint32();
                    const results = try allocator.alloc(ValueType, result_count);
                    errdefer allocator.free(results);
                    for (results) |*r| {
                        r.* = try valueTypeFromByte(try d.readByte());
                    }
                    try types.append(.{ .params = params, .results = results });
                }
            },
            3 => { // Function section
                const count = try d.readVarUint32();
                for (0..count) |_| {
                    try functions.append(try d.readVarUint32());
                }
            },
            7 => { // Export section
                const count = try d.readVarUint32();
                for (0..count) |_| {
                    const name_len = try d.readVarUint32();
                    const name_bytes = try d.readSlice(name_len);
                    const name = try allocator.dupe(u8, name_bytes);
                    errdefer allocator.free(name);
                    const kind_byte = try d.readByte();
                    const kind = switch (kind_byte) {
                        0x00 => ExportType.function,
                        0x01 => ExportType.table,
                        0x02 => ExportType.memory,
                        0x03 => ExportType.global,
                        else => return error.InvalidExportType,
                    };
                    const index = try d.readVarUint32();
                    try exports.append(.{ .name = name, .kind = kind, .index = index });
                }
            },
            10 => { // Code section
                const count = try d.readVarUint32();
                for (0..count) |_| {
                    const body_size = try d.readVarUint32();
                    const start = d.index;
                    const local_count = try d.readVarUint32();
                    var locals_list = std.ArrayList(Local).init(allocator);
                    errdefer locals_list.deinit();
                    for (0..local_count) |_| {
                        const num = try d.readVarUint32();
                        const vt = try valueTypeFromByte(try d.readByte());
                        try locals_list.append(.{ .count = num, .value_type = vt });
                    }
                    const body_len = body_size - (d.index - start) - 1;
                    const body = try d.readSlice(body_len);
                    const end_byte = try d.readByte();
                    if (end_byte != 0x0b) return error.InvalidFunctionBody;
                    const locals_alloc = try allocator.dupe(Local, locals_list.items);
                    errdefer allocator.free(locals_alloc);
                    locals_list.deinit();
                    const instrs = try parseInstructions(allocator, body);
                    errdefer freeInstructions(allocator, instrs);
                    try codes.append(.{ .locals = locals_alloc, .body = body, .instructions = instrs });
                }
            },
            else => {
                _ = try d.readSlice(section_len);
            },
        }
        if (d.index != end_index) return error.SectionSizeMismatch;
    }

    return Module{
        .types = try types.toOwnedSlice(),
        .functions = try functions.toOwnedSlice(),
        .codes = try codes.toOwnedSlice(),
        .exports = try exports.toOwnedSlice(),
    };
}

fn parseInstructions(allocator: std.mem.Allocator, data: []const u8) ![]Instruction {
    var d = Deserializer{ .data = data, .allocator = allocator };
    var list = std.ArrayList(Instruction).init(allocator);
    errdefer {
        freeInstructions(allocator, list.items);
        list.deinit();
    }
    defer list.deinit();
    while (d.index < d.data.len) {
        const opcode = try d.readByte();
        var instr: Instruction = .{ .Plain = opcode };
        switch (opcode) {
            0x02 => instr = .{ .Block = .{ .block_type = @intCast(try d.readByte()) } },
            0x03 => instr = .{ .Loop = .{ .block_type = @intCast(try d.readByte()) } },
            0x04 => instr = .{ .If = .{ .block_type = @intCast(try d.readByte()) } },
            0x0c => instr = .{ .Br = .{ .label_index = try d.readVarUint32() } },
            0x0d => instr = .{ .BrIf = .{ .label_index = try d.readVarUint32() } },
            0x0e => {
                const count = try d.readVarUint32();
                const targets = try allocator.alloc(u32, count);
                errdefer allocator.free(targets);
                for (targets) |*t| {
                    t.* = try d.readVarUint32();
                }
                const default_target = try d.readVarUint32();
                instr = .{ .BrTable = .{ .targets = targets, .default_target = default_target } };
            },
            0x0f => instr = .{ .Return = {} },
            0x10 => instr = .{ .Call = .{ .func_index = try d.readVarUint32() } },
            0x11 => {
                const type_index = try d.readVarUint32();
                const table_index = try d.readByte();
                instr = .{ .CallIndirect = .{ .type_index = type_index, .table_index = table_index } };
            },
            0x20 => instr = .{ .LocalGet = .{ .local_index = try d.readVarUint32() } },
            0x21 => instr = .{ .LocalSet = .{ .local_index = try d.readVarUint32() } },
            0x22 => instr = .{ .LocalTee = .{ .local_index = try d.readVarUint32() } },
            0x23 => instr = .{ .GlobalGet = .{ .global_index = try d.readVarUint32() } },
            0x24 => instr = .{ .GlobalSet = .{ .global_index = try d.readVarUint32() } },
            0x28 => instr = .{ .I32Load = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x29 => instr = .{ .I64Load = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x2a => instr = .{ .F32Load = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x2b => instr = .{ .F64Load = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x2c => instr = .{ .I32Load8S = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x2d => instr = .{ .I32Load8U = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x2e => instr = .{ .I32Load16S = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x2f => instr = .{ .I32Load16U = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x30 => instr = .{ .I64Load8S = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x31 => instr = .{ .I64Load8U = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x32 => instr = .{ .I64Load16S = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x33 => instr = .{ .I64Load16U = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x34 => instr = .{ .I64Load32S = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x35 => instr = .{ .I64Load32U = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x36 => instr = .{ .I32Store = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x37 => instr = .{ .I64Store = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x38 => instr = .{ .F32Store = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x39 => instr = .{ .F64Store = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x3a => instr = .{ .I32Store8 = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x3b => instr = .{ .I32Store16 = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x3c => instr = .{ .I64Store8 = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x3d => instr = .{ .I64Store16 = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x3e => instr = .{ .I64Store32 = .{ .alignment = try d.readVarUint32(), .offset = try d.readVarUint32() } },
            0x3f => instr = .{ .MemorySize = try d.readVarUint32() },
            0x40 => instr = .{ .MemoryGrow = try d.readVarUint32() },
            0x41 => instr = .{ .I32Const = try d.readVarInt32() },
            0x42 => instr = .{ .I64Const = try d.readVarInt64() },
            0x43 => {
                const bytes = try d.readSlice(4);
                const bits = std.mem.readInt(u32, @as(*const [4]u8, @ptrCast(bytes.ptr)), .little);
                instr = .{ .F32Const = @bitCast(bits) };
            },
            0x44 => {
                const bytes = try d.readSlice(8);
                const bits = std.mem.readInt(u64, @as(*const [8]u8, @ptrCast(bytes.ptr)), .little);
                instr = .{ .F64Const = @bitCast(bits) };
            },
            0x6a => instr = .{ .I32Add = {} },
            0xfc, 0xfd => {
                const start = d.index;
                _ = try d.readVarUint32();
                while (d.index < d.data.len and d.data[d.index] & 0x80 != 0) {
                    _ = try d.readByte();
                }
                instr = .{ .Misc = .{ .opcode = opcode, .bytes = d.data[start..d.index] } };
            },
            else => {},
        }
        try list.append(instr);
    }
    return list.toOwnedSlice();
}

fn freeInstructions(allocator: std.mem.Allocator, slice: []Instruction) void {
    for (slice) |inst| {
        switch (inst) {
            .BrTable => |bt| allocator.free(bt.targets),
            .Misc => {},
            else => {},
        }
    }
    allocator.free(slice);
}
