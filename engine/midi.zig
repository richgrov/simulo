const std = @import("std");

const Reader = struct {
    data: []const u8,
    read_index: usize,

    pub fn init(data: []const u8) Reader {
        return Reader{
            .data = data,
            .read_index = 0,
        };
    }

    pub fn isEof(self: *Reader) bool {
        return self.read_index >= self.data.len;
    }

    pub fn skip(self: *Reader, n: usize) void {
        self.read_index += n;
    }

    pub fn readInt(self: *Reader, comptime T: type) !T {
        const size = @divExact(@typeInfo(T).int.bits, 8);
        if (self.read_index + size > self.data.len) {
            return error.EndOfFile;
        }

        const range = self.data[self.read_index .. self.read_index + size];
        const value = std.mem.readInt(T, @ptrCast(range), .big);
        self.read_index += size;
        return value;
    }

    pub fn readVarInt(self: *Reader) !u32 {
        var result: u32 = 0;
        while (true) {
            if (self.read_index >= self.data.len) {
                return error.EndOfFile;
            }

            const byte = self.data[self.read_index];
            self.read_index += 1;

            result <<= 7;
            result |= byte & 0b01111111;
            if (byte & 0b10000000 == 0) break;
        }
        return result;
    }
};

const Mthd = struct {
    const id = ('M' << 24) | ('T' << 16) | ('h' << 8) | 'd';

    const Division = union(enum) {
        ticks_per_quarter_note: u16,
    };

    format: enum {
        one_track,
        multi_track,
        multi_file,
    },
    num_tracks: u16,
    division: Division,

    fn parse(reader: *Reader) !Mthd {
        const format = try reader.readInt(u16);
        const num_tracks = try reader.readInt(u16);
        const division = try reader.readInt(u16);

        return Mthd{
            .format = switch (format) {
                0 => .one_track,
                1 => .multi_track,
                2 => .multi_file,
                else => return error.InvalidMthdFormat,
            },
            .num_tracks = num_tracks,
            .division = switch (division >> 15) {
                0 => .{ .ticks_per_quarter_note = division },
                1 => return error.TimeCodeDivisionNotImplemented,
                else => return error.InvalidMthdDivision,
            },
        };
    }
};

const MTrk = struct {
    const id = ('M' << 24) | ('T' << 16) | ('r' << 8) | 'k';

    const Event = struct {
        time: u32,
        data: EventData,
    };

    const EventData = union(enum) {
        set_tempo: u32,
        note_on: struct {
            note: u8,
            velocity: u8,
        },
        note_off: struct {
            note: u8,
            velocity: u8,
        },
    };

    events: []Event,

    fn parse(reader: *Reader, allocator: std.mem.Allocator) !MTrk {
        var events = std.ArrayList(Event).init(allocator);
        errdefer events.deinit();

        var at_start = true;
        while (!reader.isEof()) {
            const time = try reader.readVarInt();
            if (at_start) {
                at_start = time == 0;
            }

            const status = try reader.readInt(u8);
            if (status == 0xFF) {
                if (try parseMetaEvent(reader, at_start)) |event_data| {
                    try events.append(.{
                        .time = time,
                        .data = event_data,
                    });
                }
            } else if (status >= 0xC0 and status <= 0xCF) { // program change
                reader.skip(1);
            } else if (status >= 0x80 and status <= 0x8F) { // note off
                const note = try reader.readInt(u8);
                const velocity = try reader.readInt(u8);
                try events.append(.{
                    .time = time,
                    .data = .{ .note_off = .{
                        .note = note,
                        .velocity = velocity,
                    } },
                });
            } else if (status >= 0x90 and status <= 0x9F) { // note on
                const note = try reader.readInt(u8);
                const velocity = try reader.readInt(u8);
                try events.append(.{
                    .time = time,
                    .data = .{ .note_on = .{
                        .note = note,
                        .velocity = velocity,
                    } },
                });
            } else {
                std.debug.print("???: {d} {d}\n", .{ time, status });
                break;
            }
        }

        return MTrk{ .events = try events.toOwnedSlice() };
    }

    fn parseMetaEvent(reader: *Reader, at_start: bool) !?EventData {
        const ty = try reader.readInt(u8);
        const len = try reader.readVarInt();

        switch (ty) {
            0x03 => { // track name
                if (!at_start) {
                    return error.TrackNameNotAtStart;
                }
                reader.skip(len);
                return null;
            },
            0x2F => { // end of track
                return null;
            },
            0x51 => { // set tempo
                const tempo = try reader.readInt(u24);
                return .{ .set_tempo = @intCast(tempo) };
            },
            0x58 => { // time signature
                reader.skip(4);
                return null;
            },
            else => {
                return error.UnsupportedMetaEventType;
            },
        }
    }
};

const Midi = struct {
    tracks: []MTrk,

    pub fn deinit(self: *Midi, allocator: std.mem.Allocator) void {
        for (self.tracks) |track| {
            allocator.free(track.events);
        }
        allocator.free(self.tracks);
    }
};

pub fn parseMidi(data: []const u8, allocator: std.mem.Allocator) !Midi {
    var reader = Reader.init(data);

    if (try reader.readInt(u32) != Mthd.id) {
        return error.FirstHeaderNotMthd;
    }

    const mthd_len = try reader.readInt(u32);
    var mthd_reader = Reader.init(data[reader.read_index .. reader.read_index + mthd_len]);
    const mthd = try Mthd.parse(&mthd_reader);
    _ = mthd;
    reader.read_index += mthd_len;

    var tracks = std.ArrayList(MTrk).init(allocator);
    errdefer tracks.deinit();

    while (!reader.isEof()) {
        const header = try reader.readInt(u32);
        const len = try reader.readInt(u32);
        var chunk_reader = Reader.init(data[reader.read_index .. reader.read_index + len]);
        reader.read_index += len;

        switch (header) {
            Mthd.id => return error.MthdSeenAgain,
            MTrk.id => {
                try tracks.append(try MTrk.parse(&chunk_reader, allocator));
            },
            else => {},
        }
    }

    return Midi{ .tracks = try tracks.toOwnedSlice() };
}

test "midi varints" {
    const Tester = struct {
        fn run(expected: u32, data: []const u8) !void {
            var reader = Reader.init(data);
            try std.testing.expectEqual(expected, try reader.readVarInt());
        }
    };

    try Tester.run(0, &[_]u8{0x00});
    try Tester.run(0x40, &[_]u8{0x40});
    try Tester.run(0x7F, &[_]u8{0x7F});
    try Tester.run(0x80, &[_]u8{ 0x81, 0x00 });
    try Tester.run(0x2000, &[_]u8{ 0xC0, 0x00 });
    try Tester.run(0x3FFF, &[_]u8{ 0xFF, 0x7F });
    try Tester.run(0x4000, &[_]u8{ 0x81, 0x80, 0x00 });
    try Tester.run(0x100000, &[_]u8{ 0xC0, 0x80, 0x00 });
    try Tester.run(0x1FFFFF, &[_]u8{ 0xFF, 0xFF, 0x7F });
    try Tester.run(0x200000, &[_]u8{ 0x81, 0x80, 0x80, 0x00 });
    try Tester.run(0x8000000, &[_]u8{ 0xC0, 0x80, 0x80, 0x00 });
    try Tester.run(0xFFFFFFF, &[_]u8{ 0xFF, 0xFF, 0xFF, 0x7F });
}
