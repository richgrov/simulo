const std = @import("std");

pub const Event = union(enum) {
    section: []const u8,
    pair: struct { key: []const u8, value: [:0]const u8 },
    err: struct { line: usize, message: []const u8 },
};

pub const Iterator = struct {
    const Self = @This();

    buf: [1024 * 2]u8 = undefined,
    len: usize,
    read_index: usize = 0,
    write_index: usize = 0,
    line: usize = 1,

    pub fn init(path: []const u8) !Self {
        var buf: [1024 * 2]u8 = undefined;
        const data = try std.fs.cwd().readFile(path, &buf);

        if (data.len >= buf.len - 1) {
            return error.FileTooBig; // need the last byte free for inserting a null terminator
        }

        return Self{
            .buf = buf,
            .len = data.len,
        };
    }

    fn skipWhitespace(self: *Self, newlines: bool) void {
        while (self.read_index < self.len) {
            const c = self.buf[self.read_index];
            if (c == ' ' or c == '\t' or c == '\r') {
                self.read_index += 1;
            } else if (newlines and c == '\n') {
                self.line += 1;
                self.read_index += 1;
            } else {
                break;
            }
        }
    }

    pub fn next(self: *Self) !?Event {
        while (self.read_index < self.len) {
            self.skipWhitespace(true);

            if (self.read_index >= self.len) {
                return null;
            }

            const c = self.buf[self.read_index];
            if (c == ';' or c == '#') {
                while (self.read_index < self.len and self.buf[self.read_index] != '\n') : (self.read_index += 1) {}
                continue;
            }

            break;
        }

        if (self.read_index >= self.len) {
            return null;
        }

        const c = self.buf[self.read_index];
        if (c == '[') {
            self.read_index += 1;
            const start = self.write_index;
            var end: usize = undefined;

            while (true) {
                if (self.read_index >= self.len) {
                    return error.EofInSectionName;
                }

                if (self.buf[self.read_index] == ']') {
                    end = self.write_index;
                    self.read_index += 1;

                    self.skipWhitespace(false);
                    if (self.read_index < self.len) {
                        if (self.buf[self.read_index] == '\n') {
                            self.read_index += 1;
                            self.line += 1;
                        } else {
                            return error.ExpectedNewLineAfterSection;
                        }
                    }

                    break;
                }

                self.write(self.buf[self.read_index]);
                self.read_index += 1;
            }

            return .{ .section = self.buf[start..end] };
        }

        const key_start = self.write_index;
        var key_end: usize = undefined;

        while (true) {
            if (self.read_index >= self.len) {
                return error.EofInKey;
            }

            const e = self.buf[self.read_index];
            if (!std.ascii.isAlphanumeric(e) and e != '_') {
                key_end = self.write_index;
                break;
            }

            self.write(e);
            self.read_index += 1;
        }

        if (key_start == key_end) {
            return error.EmptyKey;
        }

        self.skipWhitespace(false);

        if (self.read_index >= self.len) {
            return error.EofExpectingEquals;
        } else if (self.buf[self.read_index] != '=') {
            return self.mkError("expected '='");
        }
        self.read_index += 1;

        self.skipWhitespace(false);

        const value_start = self.write_index;
        var value_end: usize = value_start;
        while (self.read_index < self.len and self.buf[self.read_index] != '\n') : (self.read_index += 1) {
            const e = self.buf[self.read_index];
            if (e != ' ' and e != '\t' and e != '\r') {
                value_end = self.write_index + 1;
            }
            self.write(e);
        }

        self.buf[value_end] = 0;

        return .{ .pair = .{
            .key = self.buf[key_start..key_end],
            .value = @ptrCast(self.buf[value_start..value_end]),
        } };
    }

    fn write(self: *Self, c: u8) void {
        self.buf[self.write_index] = c;
        self.write_index += 1;
    }

    fn mkError(self: *Self, message: []const u8) Event {
        return .{ .err = .{ .line = self.line, .message = message } };
    }
};

const testing = std.testing;

fn mkIter(data: []u8) Iterator {
    var buf: [1024 * 2]u8 = undefined;
    @memcpy(buf[0..data.len], data);
    return .{ .buf = buf, .len = data.len };
}

test "Parses section headers" {
    const data = "[section]\n";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = mkIter(buffer);
    const event = (try iterator.next()).?;

    try testing.expect(event == .section);
    try testing.expectEqualStrings("section", event.section);
}

test "Parses key value pairs" {
    const data = "key=value\n";
    const allocator = testing.allocator;
    const buffer = try allocator.dupeZ(u8, data);
    defer allocator.free(buffer);

    var iterator = mkIter(buffer);
    const event = (try iterator.next()).?;

    try testing.expect(event == .pair);
    try testing.expectEqualStrings("key", event.pair.key);
    try testing.expectEqualStrings("value", event.pair.value);
}

test "Trims whitespace" {
    const data = "  key  =  value  \n";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = mkIter(buffer);
    const event = (try iterator.next()).?;

    try testing.expect(event == .pair);
    try testing.expectEqualStrings("key", event.pair.key);
    try testing.expectEqualStrings("value", event.pair.value);
}

test "Ignores comments" {
    const data =
        \\# This is a comment
        \\key=value
        \\; This is another comment
        \\another_key=another_value
    ;
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = mkIter(buffer);

    const event1 = (try iterator.next()).?;
    try testing.expect(event1 == .pair);
    try testing.expectEqualStrings("key", event1.pair.key);
    try testing.expectEqualStrings("value", event1.pair.value);

    try testing.expectEqualDeep(Event{ .pair = .{
        .key = "another_key",
        .value = "another_value",
    } }, try iterator.next());
}

test "Parses mixed content" {
    const data =
        \\[section1]
        \\key1=value1
        \\
        \\[section2]
        \\key2=value2
        \\# comment in between
        \\key3=value3
    ;
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = mkIter(buffer);

    const event1 = (try iterator.next()).?;
    try testing.expect(event1 == .section);
    try testing.expectEqualStrings("section1", event1.section);

    const event2 = (try iterator.next()).?;
    try testing.expect(event2 == .pair);
    try testing.expectEqualStrings("key1", event2.pair.key);

    const event3 = (try iterator.next()).?;
    try testing.expect(event3 == .section);
    try testing.expectEqualStrings("section2", event3.section);

    const event4 = (try iterator.next()).?;
    try testing.expect(event4 == .pair);
    try testing.expectEqualStrings("key2", event4.pair.key);

    const event5 = (try iterator.next()).?;
    try testing.expect(event5 == .pair);
    try testing.expectEqualStrings("key3", event5.pair.key);
}

test "Empty input returns null" {
    const data = "";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = mkIter(buffer);
    const event = try iterator.next();

    try testing.expect(event == null);
}

test "Whitespace only returns null" {
    const data = "   \t\n  \r\n   ";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = mkIter(buffer);
    const event = try iterator.next();

    try testing.expect(event == null);
}

test "Empty value" {
    const data = "key=";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = mkIter(buffer);
    const result = (try iterator.next()).?;

    try testing.expect(result == .pair);
    try testing.expectEqualStrings("key", result.pair.key);
    try testing.expectEqualStrings("", result.pair.value);
}

test "Error on unclosed section" {
    const data = "[section";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = mkIter(buffer);
    const result = iterator.next();

    try testing.expectError(error.EofInSectionName, result);
}

test "Error on extra after section" {
    const data = "[section] extra";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = mkIter(buffer);
    const result = iterator.next();

    try testing.expectError(error.ExpectedNewLineAfterSection, result);
}

test "Error on empty key" {
    const data = "=value";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = mkIter(buffer);
    const result = iterator.next();

    try testing.expectError(error.EmptyKey, result);
}

test "Preserves special characters" {
    const data = "key=value with spaces and symbols!@#$\n";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = mkIter(buffer);
    const event = (try iterator.next()).?;

    try testing.expect(event == .pair);
    try testing.expectEqualStrings("key", event.pair.key);
    try testing.expectEqualStrings("value with spaces and symbols!@#$", event.pair.value);
}

test "Allows spaces in sections" {
    const data = "[section name]\n";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = mkIter(buffer);
    const event = (try iterator.next()).?;

    try testing.expect(event == .section);
    try testing.expectEqualStrings("section name", event.section);
}
