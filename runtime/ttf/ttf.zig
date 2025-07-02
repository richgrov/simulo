const std = @import("std");
const Reader = @import("./reader.zig").Reader;

pub const Ttf = struct {
    allocator: std.mem.Allocator,
    data: []const u8,

    units_per_em: u16,
    index_to_loc_format: i16,
    num_glyphs: u16,
    loca: []u32,
    glyf_offset: u32,
    glyf_length: u32,

    pub fn deinit(self: *Ttf) void {
        self.allocator.free(self.loca);
    }

    pub fn glyphSlice(self: *const Ttf, index: u16) []const u8 {
        const start = self.glyf_offset + self.loca[index];
        const end = self.glyf_offset + self.loca[index + 1];
        return self.data[start..end];
    }
};

const SCALAR_TYPE_TRUE1: u32 = 0x74727565;
const SCALAR_TYPE_TRUE2: u32 = 0x00010000;
const HEAD_MAGIC_NUMBER: u32 = 0x5F0F3CF5;

pub fn parse(allocator: std.mem.Allocator, data: []const u8) !Ttf {
    var reader = Reader.init(data);

    const scaler_type = try reader.readU32();
    if (scaler_type != SCALAR_TYPE_TRUE1 and scaler_type != SCALAR_TYPE_TRUE2) {
        return error.InvalidScalarType;
    }

    const num_tables = try reader.readU16();
    _ = try reader.readU16(); // search range
    _ = try reader.readU16(); // entry selector
    _ = try reader.readU16(); // range shift

    var head_offset: u32 = 0;
    var maxp_offset: u32 = 0;
    var loca_offset: u32 = 0;
    var glyf_offset: u32 = 0;
    var glyf_length: u32 = 0;

    for (0..num_tables) |_| {
        const tag = try reader.readU32();
        _ = try reader.readU32(); // checksum
        const offset = try reader.readU32();
        const length = try reader.readU32();

        switch (tag) {
            0x68656164 => head_offset = offset, // 'head'
            0x6d617870 => maxp_offset = offset, // 'maxp'
            0x6c6f6361 => loca_offset = offset, // 'loca'
            0x676c7966 => { // 'glyf'
                glyf_offset = offset;
                glyf_length = length;
            },
            else => {},
        }
    }

    if (head_offset == 0 or maxp_offset == 0 or loca_offset == 0 or glyf_offset == 0) {
        return error.MissingTable;
    }

    var head_reader = Reader.init(data[head_offset..]);
    _ = try head_reader.readFixed(); // version
    _ = try head_reader.readFixed(); // font revision
    _ = try head_reader.readU32(); // checksum adjustment
    if (try head_reader.readU32() != HEAD_MAGIC_NUMBER) {
        return error.InvalidMagic;
    }
    _ = try head_reader.readU16(); // flags
    const units_per_em = try head_reader.readU16();
    head_reader.pos += 8 + 8; // created and modified datetimes
    _ = try head_reader.readI16(); // xMin
    _ = try head_reader.readI16(); // yMin
    _ = try head_reader.readI16(); // xMax
    _ = try head_reader.readI16(); // yMax
    _ = try head_reader.readU16(); // macStyle
    _ = try head_reader.readU16(); // lowestRecPPEM
    _ = try head_reader.readI16(); // fontDirectionHint
    const index_to_loc_format = try head_reader.readI16();
    _ = try head_reader.readI16(); // glyphDataFormat

    var maxp_reader = Reader.init(data[maxp_offset..]);
    _ = try maxp_reader.readFixed();
    const num_glyphs = try maxp_reader.readU16();

    var loca_reader = Reader.init(data[loca_offset..]);
    var loca = try allocator.alloc(u32, num_glyphs + 1);
    if (index_to_loc_format == 0) {
        for (0..loca.len) |i| {
            const val = try loca_reader.readU16();
            loca[i] = @as(u32, val) * 2;
        }
    } else {
        for (0..loca.len) |i| {
            loca[i] = try loca_reader.readU32();
        }
    }

    return Ttf{
        .allocator = allocator,
        .data = data,
        .units_per_em = units_per_em,
        .index_to_loc_format = index_to_loc_format,
        .num_glyphs = num_glyphs,
        .loca = loca,
        .glyf_offset = glyf_offset,
        .glyf_length = glyf_length,
    };
}
