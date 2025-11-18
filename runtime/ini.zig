const std = @import("std");

pub const Event = union(enum) {
    section: []const u8,
    pair: struct { key: []const u8, value: []const u8 },
};

pub const Iterator = struct {
    const Self = @This();
    const BufferSize = 300;

    data: []u8,
    read_index: usize = 0,

    pub fn init(data: []u8) !Self {
        return Self{
            .data = data,
        };
    }

    fn skipWhitespace(self: *Self, newlines: bool) void {
        while (self.read_index < self.data.len) {
            const c = self.data[self.read_index];
            if (c == ' ' or c == '\t' or c == '\r' or (newlines and c == '\n')) {
                self.read_index += 1;
            } else {
                break;
            }
        }
    }

    pub fn next(self: *Self) !?Event {
        while (self.read_index < self.data.len) {
            self.skipWhitespace(true);

            if (self.read_index >= self.data.len) {
                return null;
            }

            const c = self.data[self.read_index];
            if (c == ';' or c == '#') {
                while (self.read_index < self.data.len) {
                    self.read_index += 1;
                    if (self.data[self.read_index] == '\n') {
                        break;
                    }
                }
                continue;
            }

            break;
        }

        if (self.read_index >= self.data.len) {
            return null;
        }

        const c = self.data[self.read_index];
        if (c == '[') {
            self.read_index += 1;
            const start = self.read_index;
            var end: usize = undefined;

            while (true) {
                if (self.read_index >= self.data.len) {
                    return error.EofInSectionName;
                }

                if (self.data[self.read_index] == ']') {
                    end = self.read_index;
                    self.read_index += 1;

                    self.skipWhitespace(false);
                    if (self.read_index < self.data.len) {
                        if (self.data[self.read_index] == '\n') {
                            self.read_index += 1;
                        } else {
                            return error.ExpectedNewLineAfterSection;
                        }
                    }

                    break;
                }

                self.read_index += 1;
            }

            return .{ .section = self.data[start..end] };
        }

        const key_start = self.read_index;
        var key_end: usize = undefined;
        var last_non_space: usize = self.read_index;

        while (true) {
            if (self.read_index >= self.data.len) {
                return error.EofInKey;
            }

            const e = self.data[self.read_index];
            if (e == '=') {
                key_end = last_non_space;
                self.read_index += 1;
                break;
            } else if (e == '\n' or e == '\r') {
                return error.EndOfLineInKey;
            } else if (e != ' ' and e != '\t') {
                last_non_space = self.read_index;
            }
            self.read_index += 1;
        }

        if (key_start == key_end) {
            return error.EmptyKey;
        }

        self.skipWhitespace(false);

        const value_start = self.read_index;
        var value_end: usize = self.read_index;
        last_non_space = self.read_index;
        while (self.read_index < self.data.len) {
            const e = self.data[self.read_index];
            if (e == '\n') {
                value_end = last_non_space + 1;
                break;
            } else if (e != ' ' and e != '\t' and e != '\r') {
                last_non_space = self.read_index;
            }
            self.read_index += 1;
        }

        return .{ .pair = .{
            .key = self.data[key_start .. key_end + 1],
            .value = self.data[value_start..value_end],
        } };
    }
};

const testing = std.testing;

test "Parses section headers" {
    const data = "[section]\n";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = try Iterator.init(buffer);
    const event = (try iterator.next()).?;

    try testing.expect(event == .section);
    try testing.expectEqualStrings("section", event.section);
}

test "Parses key value pairs" {
    const data = "key=value\n";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = try Iterator.init(buffer);
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

    var iterator = try Iterator.init(buffer);
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

    var iterator = try Iterator.init(buffer);

    const event1 = (try iterator.next()).?;
    try testing.expect(event1 == .pair);
    try testing.expectEqualStrings("key", event1.pair.key);

    const event2 = (try iterator.next()).?;
    try testing.expect(event2 == .pair);
    try testing.expectEqualStrings("another_key", event2.pair.key);
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

    var iterator = try Iterator.init(buffer);

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

    var iterator = try Iterator.init(buffer);
    const event = try iterator.next();

    try testing.expect(event == null);
}

test "Whitespace only returns null" {
    const data = "   \t\n  \r\n   ";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = try Iterator.init(buffer);
    const event = try iterator.next();

    try testing.expect(event == null);
}

test "Empty value" {
    const data = "key=";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = try Iterator.init(buffer);
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

    var iterator = try Iterator.init(buffer);
    const result = iterator.next();

    try testing.expectError(error.EofInSectionName, result);
}

test "Error on extra after section" {
    const data = "[section] extra";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = try Iterator.init(buffer);
    const result = iterator.next();

    try testing.expectError(error.ExpectedNewLineAfterSection, result);
}

test "Error on empty key" {
    const data = "=value";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = try Iterator.init(buffer);
    const result = iterator.next();

    try testing.expectError(error.EmptyKey, result);
}

test "Preserves special characters" {
    const data = "key=value with spaces and symbols!@#$\n";
    const allocator = testing.allocator;
    const buffer = try allocator.dupe(u8, data);
    defer allocator.free(buffer);

    var iterator = try Iterator.init(buffer);
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

    var iterator = try Iterator.init(buffer);
    const event = (try iterator.next()).?;

    try testing.expect(event == .section);
    try testing.expectEqualStrings("section name", event.section);
}
