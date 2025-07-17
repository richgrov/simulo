const std = @import("std");

const Reader = struct {
    data: []u8,
    read_index: usize,

    pub fn init(data: []u8) Reader {
        return Reader{
            .data = data,
            .read_index = 0,
        };
    }

    pub fn readInt(self: *Reader, comptime T: type) !T {
        const end = self.read_index + @sizeOf(T);
        if (end > self.data.len) {
            return error.PacketTooShort;
        }

        const value = std.mem.readInt(T, @ptrCast(self.data[self.read_index..end]), .big);
        self.read_index += @sizeOf(T);
        return value;
    }

    pub fn readString(self: *Reader, comptime max_len: usize, allocator: std.mem.Allocator) ![]u8 {
        const len: usize = @intCast(try self.readInt(u16));
        if (len > max_len) {
            return error.InvalidStringLength;
        }

        const end = self.read_index + len;
        if (end > self.data.len) {
            return error.PacketTooShort;
        }

        const str = self.data[self.read_index..end];
        self.read_index += len;

        return try allocator.dupe(u8, str);
    }
};

pub const DownloadFile = struct {
    url: []u8,
    hash: [32]u8,
};

pub const Packet = union(enum) {
    download: struct {
        program_url: []u8,
        program_hash: [32]u8,
        assets: []const DownloadFile,
    },

    pub fn from(allocator: std.mem.Allocator, data: []u8) !Packet {
        var reader = Reader.init(data);
        switch (try reader.readInt(u8)) {
            0 => {
                const program_url = try reader.readString(1024, allocator);
                const program_hash: [32]u8 = @bitCast(try reader.readInt(u256));

                const num_files = try reader.readInt(u8);
                if (num_files > 16) {
                    return error.InvalidNumFiles;
                }

                const assets = try allocator.alloc(DownloadFile, num_files);
                for (assets) |*asset| {
                    asset.url = try reader.readString(1024, allocator);
                    asset.hash = @bitCast(try reader.readInt(u256));
                }

                return Packet{ .download = .{
                    .program_url = program_url,
                    .program_hash = program_hash,
                    .assets = assets,
                } };
            },
            else => return error.UnknownPacketId,
        }
    }

    pub fn deinit(self: *Packet, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .download => |download| {
                allocator.free(download.program_url);
                for (download.assets) |asset| {
                    allocator.free(asset.url);
                }
                allocator.free(download.assets);
            },
        }
    }
};
