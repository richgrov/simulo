const std = @import("std");

pub const ValueType = enum(i8) {
    i32 = 0x7f,
    i64 = 0x7e,
    f32 = 0x7d,
    f64 = 0x7c,
};

pub const Local = struct {
    count: u32,
    value_type: ValueType,
};

pub const FunctionType = struct {
    params: []ValueType,
    results: []ValueType,
};

pub const Instruction = struct {
    opcode: u8,
    immediates: []const u8,
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

    pub fn deinit(self: *Module, allocator: std.mem.Allocator) void {
        for (self.types) |*t| {
            allocator.free(t.params);
            allocator.free(t.results);
        }
        allocator.free(self.types);
        allocator.free(self.functions);
        for (self.codes) |*c| {
            allocator.free(c.locals);
            allocator.free(c.instructions);
        }
        allocator.free(self.codes);
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
            allocator.free(code.instructions);
        }
        codes.deinit();
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
                    errdefer allocator.free(instrs);
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
    };
}

fn parseInstructions(allocator: std.mem.Allocator, data: []const u8) ![]Instruction {
    var d = Deserializer{ .data = data, .allocator = allocator };
    var list = std.ArrayList(Instruction).init(allocator);
    errdefer list.deinit();
    while (d.index < d.data.len) {
        const opcode = try d.readByte();
        const start = d.index;
        switch (opcode) {
            0x02, 0x03, 0x04 => {
                _ = try d.readByte();
            },
            0x0c, 0x0d => {
                _ = try d.readVarUint32();
            },
            0x0e => {
                const count = try d.readVarUint32();
                for (0..count + 1) |_| {
                    _ = try d.readVarUint32();
                }
            },
            0x10 => {
                _ = try d.readVarUint32();
            },
            0x11 => {
                _ = try d.readVarUint32();
                _ = try d.readByte();
            },
            0x20, 0x21, 0x22, 0x23, 0x24 => {
                _ = try d.readVarUint32();
            },
            0x28...0x40 => {
                _ = try d.readVarUint32();
                _ = try d.readVarUint32();
            },
            0x41 => {
                _ = try d.readVarInt32();
            },
            0x42 => {
                _ = try d.readVarInt64();
            },
            0x43 => {
                _ = try d.readSlice(4);
            },
            0x44 => {
                _ = try d.readSlice(8);
            },
            0xfc, 0xfd => {
                _ = try d.readVarUint32();
                while (d.index < d.data.len and d.data[d.index] & 0x80 != 0) {
                    _ = try d.readByte();
                }
            },
            else => {},
        }
        try list.append(.{ .opcode = opcode, .immediates = d.data[start..d.index] });
    }
    return list.toOwnedSlice();
}
