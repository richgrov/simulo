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
    cmap_offset: u32,
    cmap_format: u16,

    pub fn deinit(self: *Ttf) void {
        self.allocator.free(self.loca);
    }

    pub fn glyphSlice(self: *const Ttf, index: u16) []const u8 {
        const start = self.glyf_offset + self.loca[index];
        const end = self.glyf_offset + self.loca[index + 1];
        return self.data[start..end];
    }

    pub fn glyphIndex(self: *const Ttf, codepoint: u32) !u16 {
        var r = Reader.init(self.data[self.cmap_offset..]);
        const format = try r.readU16();
        if (format != self.cmap_format) return error.InvalidCmap;
        if (format == 4) {
            _ = try r.readU16(); // length
            _ = try r.readU16(); // language
            const seg_count = try r.readU16() / 2;
            const searchRange = try r.readU16();
            const entrySelector = try r.readU16();
            const rangeShift = try r.readU16();
            const end_count_pos = r.pos;
            const end_codes = self.data[self.cmap_offset + end_count_pos ..];
            const start_codes_pos = end_count_pos + @as(usize, seg_count) * 2 + 2;
            const start_codes = self.data[self.cmap_offset + start_codes_pos ..];
            const delta_pos = start_codes_pos + @as(usize, seg_count) * 2;
            const deltas = self.data[self.cmap_offset + delta_pos ..];
            const ro_pos = delta_pos + @as(usize, seg_count) * 2;
            const range_offsets = self.data[self.cmap_offset + ro_pos ..];
            const glyph_array_pos = ro_pos + @as(usize, seg_count) * 2;
            const code = @as(u16, @intCast(codepoint));

            var search = end_count_pos;
            if (codepoint >= std.mem.readInt(u16, end_codes[rangeShift .. rangeShift + 2], .big)) {
                search += rangeShift;
            }
            search -= 2;
            var sr = searchRange;
            var es = entrySelector;
            while (es > 0) : (es -= 1) {
                sr >>= 1;
                const end_val = std.mem.readInt(u16, end_codes[search + sr .. search + sr + 2], .big);
                if (code > end_val) {
                    search += sr;
                }
            }
            search += 2;
            const item = @as(usize, (search - end_count_pos) / 2);
            const start_val = std.mem.readInt(u16, start_codes[(item * 2)..(item * 2 + 2)], .big);
            const end_val = std.mem.readInt(u16, end_codes[(item * 2)..(item * 2 + 2)], .big);
            if (code < start_val or code > end_val) return 0;
            const delta = std.mem.readInt(u16, deltas[(item * 2)..(item * 2 + 2)], .big);
            const ro = std.mem.readInt(u16, range_offsets[(item * 2)..(item * 2 + 2)], .big);
            if (ro == 0) {
                return @intCast(u16, (code + delta) & 0xFFFF);
            }
            const glyph_offset = ro + (code - start_val) * 2;
            const pos = glyph_array_pos + glyph_offset + item * 2;
            const glyph = std.mem.readInt(u16, self.data[self.cmap_offset + pos .. self.cmap_offset + pos + 2], .big);
            if (glyph == 0) return 0;
            return @intCast(u16, (glyph + delta) & 0xFFFF);
        } else if (format == 12) {
            _ = try r.readU16(); // reserved
            _ = try r.readU32(); // length
            _ = try r.readU32(); // language
            const ngroups = try r.readU32();
            var low: u32 = 0;
            var high: u32 = ngroups;
            while (low < high) {
                const mid = low + ((high - low) >> 1);
                const group_pos = self.cmap_offset + 16 + mid * 12;
                const start_char = std.mem.readInt(u32, self.data[group_pos .. group_pos + 4], .big);
                const end_char = std.mem.readInt(u32, self.data[group_pos + 4 .. group_pos + 8], .big);
                if (codepoint < start_char) {
                    high = mid;
                } else if (codepoint > end_char) {
                    low = mid + 1;
                } else {
                    const start_glyph = std.mem.readInt(u32, self.data[group_pos + 8 .. group_pos + 12], .big);
                    return @as(u16, @intCast(start_glyph + codepoint - start_char));
                }
            }
            return 0;
        } else {
            return error.UnsupportedCmap;
        }
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
    var cmap_offset: u32 = 0;
    var cmap_length: u32 = 0;

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
            0x636d6170 => { // 'cmap'
                cmap_offset = offset;
                cmap_length = length;
            },
            else => {},
        }
    }

    if (head_offset == 0 or maxp_offset == 0 or loca_offset == 0 or glyf_offset == 0 or cmap_offset == 0) {
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

    var cmap_reader = Reader.init(data[cmap_offset..]);
    _ = try cmap_reader.readU16(); // version
    const num_enc = try cmap_reader.readU16();
    var best_offset: u32 = 0;
    var best_format: u16 = 0;
    for (0..num_enc) |_| {
        const platform = try cmap_reader.readU16();
        const encoding = try cmap_reader.readU16();
        const sub_offset = try cmap_reader.readU32();
        const pos = cmap_offset + sub_offset;
        var sub = Reader.init(data[pos..]);
        const format = try sub.readU16();
        const acceptable = (platform == 3 and (encoding == 1 or encoding == 10)) or (platform == 0);
        if (acceptable and (format == 4 or format == 12)) {
            best_offset = pos;
            best_format = format;
            if (format == 12) break; // prefer 32-bit encoding
        }
    }
    if (best_offset == 0)
        return error.UnsupportedCmap;

    return Ttf{
        .allocator = allocator,
        .data = data,
        .units_per_em = units_per_em,
        .index_to_loc_format = index_to_loc_format,
        .num_glyphs = num_glyphs,
        .loca = loca,
        .glyf_offset = glyf_offset,
        .glyf_length = glyf_length,
        .cmap_offset = best_offset,
        .cmap_format = best_format,
    };
}

const GlyphMod = @import("./glyph.zig");
const Glyph = GlyphMod.Glyph;
const Point = GlyphMod.Point;

pub fn parseGlyph(ttf: *const Ttf, allocator: std.mem.Allocator, index: u16) !Glyph {
    const slice = ttf.glyphSlice(index);
    if (slice.len == 0) return error.EmptyGlyph;

    var r = Reader.init(slice);
    const numberOfContours = try r.readI16();
    const x_min = try r.readI16();
    const y_min = try r.readI16();
    const x_max = try r.readI16();
    const y_max = try r.readI16();

    if (numberOfContours < 0)
        return error.CompositeGlyph; // composite glyphs not yet supported

    var end_pts = try allocator.alloc(u16, @intCast(numberOfContours));
    for (end_pts, 0..) |*pt, i| {
        pt.* = try r.readU16();
    }

    const instruction_length = try r.readU16();
    var instructions = try allocator.alloc(u8, instruction_length);
    for (instructions, 0..) |*b, i| {
        b.* = try r.readU8();
    }

    const num_points = @as(usize, end_pts[end_pts.len - 1]) + 1;
    var flags = try allocator.alloc(u8, num_points);

    var idx: usize = 0;
    while (idx < num_points) {
        const flag = try r.readU8();
        var repeat: usize = 1;
        if (flag & 0x08 != 0) {
            repeat = try r.readU8() + 1;
        }
        for (0..repeat) |_| {
            if (idx >= num_points) break;
            flags[idx] = flag;
            idx += 1;
        }
    }

    var xs = try allocator.alloc(i16, num_points);
    var ys = try allocator.alloc(i16, num_points);

    var x: i32 = 0;
    for (0..num_points) |i| {
        const flag = flags[i];
        if ((flag & 0x02) != 0) {
            const dx = try r.readU8();
            x += if ((flag & 0x10) != 0) dx else -@as(i32, dx);
        } else {
            if ((flag & 0x10) == 0) {
                x += try r.readI16();
            }
        }
        xs[i] = @as(i16, x);
    }

    var y: i32 = 0;
    for (0..num_points) |i| {
        const flag = flags[i];
        if ((flag & 0x04) != 0) {
            const dy = try r.readU8();
            y += if ((flag & 0x20) != 0) dy else -@as(i32, dy);
        } else {
            if ((flag & 0x20) == 0) {
                y += try r.readI16();
            }
        }
        ys[i] = @as(i16, y);
    }

    var points = try allocator.alloc(Point, num_points);
    for (0..num_points) |i| {
        points[i] = Point{ .x = xs[i], .y = ys[i], .on_curve = (flags[i] & 0x01) != 0 };
    }

    allocator.free(xs);
    allocator.free(ys);
    allocator.free(flags);

    return Glyph{
        .bbox = .{ .x_min = x_min, .y_min = y_min, .x_max = x_max, .y_max = y_max },
        .end_pts = end_pts,
        .instructions = instructions,
        .points = points,
    };
}
