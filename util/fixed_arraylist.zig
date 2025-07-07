pub fn FixedArrayList(comptime T: type, comptime capacity: u32) type {
    return struct {
        data: [capacity]T = undefined,
        len: u32 = 0,

        const Self = @This();

        pub fn init() Self {
            return .{};
        }

        pub fn append(self: *Self, item: T) !void {
            if (self.len == capacity) return error.OutOfMemory;
            self.data[self.len] = item;
            self.len += 1;
        }

        pub fn insert(self: *Self, index: u32, item: T) !void {
            if (self.len == capacity) return error.OutOfMemory;
            if (index > self.len) return error.InvalidIndex;

            var i = self.len;
            while (i > index) : (i -= 1) {
                self.data[i] = self.data[i - 1];
            }

            self.data[index] = item;
            self.len += 1;
        }

        pub fn get(self: *Self, index: u32) ?T {
            if (index >= self.len) return null;
            return self.data[index];
        }

        pub fn swapDelete(self: *Self, index: u32) !void {
            if (index >= self.len) return error.InvalidIndex;
            if (index == self.len - 1) {
                self.len -= 1;
                return;
            }

            self.data[index] = self.data[self.len - 1];
            self.len -= 1;
        }

        pub fn items(self: *const Self) []const T {
            return self.data[0..self.len];
        }
    };
}

const std = @import("std");

test "basic append and get" {
    var list = FixedArrayList(u8, 3).init();

    try list.append(1);
    try list.append(2);
    try list.append(3);
    try std.testing.expectEqual(@as(u32, 3), list.len);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3 }, list.items());

    try std.testing.expectError(error.OutOfMemory, list.append(4));
    try std.testing.expectEqual(@as(?u8, 2), list.get(1));
    try std.testing.expectEqual(@as(?u8, null), list.get(5));
}

test "insert and swapDelete" {
    var list = FixedArrayList(u8, 4).init();
    try list.append(1);
    try list.append(2);
    try list.append(4);

    try list.insert(2, 3);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3, 4 }, list.items());

    try list.swapDelete(1);
    try std.testing.expectEqual(@as(u32, 3), list.len);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 4, 3 }, list.items());
}
