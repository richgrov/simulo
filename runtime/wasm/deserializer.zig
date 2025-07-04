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

pub const Code = struct {
    locals: []Local,
    body: []const u8,
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
            allocator.free(code.body);
            allocator.free(code.locals);
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
                    try codes.append(.{ .locals = locals_alloc, .body = body });
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
