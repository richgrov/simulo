const std = @import("std");

const fs_storage = @import("../fs_storage.zig");

const util = @import("util");

const engine = @import("engine");
const profile = engine.profiler;

const Reader = struct {
    data: []const u8,
    read_index: usize,

    pub fn init(data: []const u8) Reader {
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

    pub fn readFull(self: *Reader, dest: []u8) !void {
        if (self.read_index + dest.len > self.data.len) {
            return error.PacketTooShort;
        }
        @memcpy(dest, self.data[self.read_index .. self.read_index + dest.len]);
        self.read_index += dest.len;
    }

    pub fn readString(self: *Reader, comptime max_len: usize, allocator: std.mem.Allocator) ![]const u8 {
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

pub const PacketWriteError = error{PacketTooLong};

pub const Writer = struct {
    const max_capacity = 1024;
    data: util.FixedArrayList(u8, max_capacity),

    pub fn init() Writer {
        return Writer{
            .data = util.FixedArrayList(u8, max_capacity).init(),
        };
    }

    pub fn writeInt(self: *Writer, comptime T: type, value: T) PacketWriteError!void {
        const end = self.data.len + @sizeOf(T);
        if (end > max_capacity) {
            return error.PacketTooLong;
        }

        std.mem.writeInt(T, @ptrCast(self.data.data[self.data.len..end]), value, .big);
        self.data.len += @sizeOf(T);
    }

    pub fn writeString(self: *Writer, value: []const u8) PacketWriteError!void {
        try self.writeInt(u16, @intCast(value.len));
        try self.writeFull(value);
    }

    pub fn writeFull(self: *Writer, value: []const u8) PacketWriteError!void {
        if (self.data.len + value.len > max_capacity) {
            return error.PacketTooLong;
        }

        @memcpy(self.data.data[self.data.len..], value);
        self.data.len += @intCast(value.len);
    }

    pub fn bytes(self: *Writer) []u8 {
        return self.data.itemsMut();
    }
};

pub fn outboundProfile(profiler: []const u8, labels: profile.Labels, logs: []const profile.Logs) PacketWriteError!Writer {
    var writer = Writer.init();
    try writer.writeString(profiler);
    try writer.writeInt(u8, @intCast(labels.len));
    for (labels.items()) |label| {
        try writer.writeString(label);
    }

    try writer.writeInt(u16, @intCast(logs.len));
    for (logs) |log| {
        for (log.items()) |log_point| {
            try writer.writeInt(u32, log_point.label);
            try writer.writeInt(u32, log_point.us);
        }
    }

    return writer;
}

pub const DownloadFile = struct {
    url: []const u8,
    asset: fs_storage.ProgramAsset,
};

pub const Packet = union(enum) {
    download: struct {
        program_url: []const u8,
        program_hash: [32]u8,
        files: []const DownloadFile,
    },

    pub fn from(allocator: std.mem.Allocator, data: []const u8) !Packet {
        var reader = Reader.init(data);
        switch (try reader.readInt(u8)) {
            0 => {
                const program_url = try reader.readString(1024, allocator);
                var program_hash: [32]u8 = undefined;
                try reader.readFull(&program_hash);

                const num_files = try reader.readInt(u8);
                if (num_files > 16) {
                    return error.InvalidNumFiles;
                }

                const files = try allocator.alloc(DownloadFile, num_files);
                for (files) |*file| {
                    const name = try reader.readString(fs_storage.max_asset_name_len, allocator);
                    defer allocator.free(name);
                    file.asset.name = util.FixedArrayList(u8, fs_storage.max_asset_name_len).initFrom(name) catch unreachable;

                    file.url = try reader.readString(1024, allocator);

                    try reader.readFull(&file.asset.hash);
                }

                return Packet{ .download = .{
                    .program_url = program_url,
                    .program_hash = program_hash,
                    .files = files,
                } };
            },
            else => return error.UnknownPacketId,
        }
    }

    pub fn deinit(self: *Packet, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .download => |download| {
                allocator.free(download.program_url);
                for (download.files) |file| {
                    allocator.free(file.url);
                }
                allocator.free(download.files);
            },
        }
    }
};
