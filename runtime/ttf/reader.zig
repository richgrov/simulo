const std = @import("std");

pub const Reader = struct {
    data: []const u8,
    pos: usize = 0,

    pub fn init(data: []const u8) Reader {
        return .{ .data = data, .pos = 0 };
    }

    fn readInt(self: *Reader, comptime T: type) !T {
        if (self.pos + @sizeOf(T) > self.data.len) {
            return error.EndOfStream;
        }
        const value = std.mem.readInt(T, @ptrCast(self.data[self.pos .. self.pos + @sizeOf(T)]), .big);
        self.pos += @sizeOf(T);
        return value;
    }

    pub fn readU8(self: *Reader) !u8 {
        return try self.readInt(u8);
    }

    pub fn readI16(self: *Reader) !i16 {
        return try self.readInt(i16);
    }

    pub fn readU16(self: *Reader) !u16 {
        return try self.readInt(u16);
    }

    pub fn readU32(self: *Reader) !u32 {
        return try self.readInt(u32);
    }

    pub fn readU64(self: *Reader) !u64 {
        return try self.readInt(u64);
    }

    pub fn readFixed(self: *Reader) !f64 {
        const raw = try self.readU32();
        return @as(f64, @floatFromInt(raw)) / 65536.0;
    }

    pub fn seek(self: *Reader, pos: usize) !void {
        if (pos > self.data.len) return error.EndOfStream;
        self.pos = pos;
    }

    pub fn position(self: *Reader) usize {
        return self.pos;
    }
};
