const std = @import("std");
const testing = std.testing;

pub fn FixedSlab(T: type, capacity: u32) type {
    const Cell = union {
        data: T,
        next: u32,
    };

    return struct {
        data: [capacity]Cell,
        next_free: u32,

        const Self = @This();

        pub fn init() Self {
            var data: [capacity]Cell = undefined;
            for (0..capacity) |i_usize| {
                const i: u32 = @intCast(i_usize);
                if (i == capacity - 1) {
                    data[i] = .{ .next = std.math.maxInt(u32) };
                } else {
                    data[i] = .{ .next = i + 1 };
                }
            }

            return .{
                .data = data,
                .next_free = 0,
            };
        }

        pub fn append(self: *Self, value: T) !std.meta.Tuple(&[_]type{ u32, *T }) {
            if (self.next_free == std.math.maxInt(u32)) {
                return error.Full;
            }

            const index = self.next_free;
            self.next_free = self.data[index].next;
            self.data[index] = .{ .data = value };
            return .{ index, &self.data[index].data };
        }

        pub fn get(self: *Self, index: u32) ?*T {
            if (index >= self.data.len) {
                return null;
            }
            return &self.data[index].data;
        }

        pub fn delete(self: *Self, index: u32) !void {
            if (index >= self.data.len) {
                return error.InvalidIndex;
            }

            self.data[index] = .{ .next = self.next_free };
            self.next_free = index;
        }
    };
}
