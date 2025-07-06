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
            const index = self.sparse[value];
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
