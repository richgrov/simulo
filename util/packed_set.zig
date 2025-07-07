const std = @import("std");
const builtin = @import("builtin");

const FixedArrayList = @import("fixed_arraylist.zig").FixedArrayList;

pub fn SparseIntSet(T: type, comptime capacity: usize) type {
    return struct {
        sparse: [capacity]u32 = [_]u32{std.math.maxInt(u32)} ** capacity,
        dense: [capacity]T = undefined,
        len: u32 = 0,

        const Self = @This();

        pub fn put(self: *Self, value: T) !void {
            if (self.len == capacity) {
                return error.Full;
            }

            if (self.sparse[value] != std.math.maxInt(u32)) {
                return;
            }

            self.dense[self.len] = value;
            self.sparse[value] = self.len;
            self.len += 1;
        }

        pub fn items(self: *const Self) []const T {
            return self.dense[0..self.len];
        }

        pub fn delete(self: *Self, value: T) !void {
            std.debug.assert(self.len > 0);

            const index = self.sparse[value];
            self.sparse[value] = std.math.maxInt(u32);
            if (index == self.len - 1) {
                self.len -= 1;
            } else {
                const new_value = self.dense[self.len - 1];
                self.dense[index] = new_value;
                self.sparse[new_value] = index;
                self.len -= 1;
            }
        }
    };
}

test "put and capacity" {
    var set = SparseIntSet(u8, 3){};
    try set.put(0);
    try set.put(1);
    try set.put(2);
    try std.testing.expectEqual(@as(u32, 3), set.len);
    try std.testing.expectError(error.Full, set.put(0));
}

test "duplicate and delete" {
    var set = SparseIntSet(u8, 5){};
    try set.put(1);
    try set.put(3);
    try set.put(4);
    try set.put(1); // duplicate should do nothing
    try std.testing.expectEqual(@as(u32, 3), set.len);

    try set.delete(3);
    try std.testing.expectEqual(@as(u32, 2), set.len);
    const items = set.items();
    try std.testing.expect(items[0] != 3 and items[1] != 3);
}
