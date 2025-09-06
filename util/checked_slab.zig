const std = @import("std");
const testing = std.testing;

pub fn CheckedSlab(T: type) type {
    const Cell = union(enum) {
        data: T,
        next: usize,
    };

    return struct {
        data: std.array_list.Managed(Cell),
        next_free: usize,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            var data = std.array_list.Managed(Cell).init(allocator);
            try data.resize(capacity);
            for (0..capacity) |i| {
                if (i == capacity - 1) {
                    data.items[i] = .{ .next = std.math.maxInt(usize) };
                } else {
                    data.items[i] = .{ .next = i + 1 };
                }
            }

            return .{
                .data = data,
                .next_free = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        pub fn insert(self: *Self, value: T) error{OutOfMemory}!std.meta.Tuple(&[_]type{ usize, *T }) {
            if (self.next_free == std.math.maxInt(usize)) {
                const index = self.data.items.len;
                try self.data.append(.{ .data = value });
                return .{ index, &self.data.items[index].data };
            }

            const index = self.next_free;
            self.next_free = self.data.items[index].next;
            self.data.items[index] = .{ .data = value };
            return .{ index, &self.data.items[index].data };
        }

        pub fn get(self: *Self, index: usize) ?*T {
            if (index >= self.data.items.len) {
                return null;
            }

            return switch (self.data.items[index]) {
                .data => |*data| data,
                .next => null,
            };
        }

        pub fn num_cells(self: *Self) usize {
            return self.data.items.len;
        }

        pub fn delete(self: *Self, index: usize) !void {
            if (index >= self.data.items.len) {
                return error.InvalidIndex;
            }

            switch (self.data.items[index]) {
                .data => {},
                .next => return error.InvalidIndex,
            }

            self.data.items[index] = .{ .next = self.next_free };
            self.next_free = index;
        }
    };
}

test "CheckedSlab insertion" {
    const allocator = testing.allocator;
    var slab = try CheckedSlab(u32).init(allocator, 3);
    defer slab.deinit();

    const index1, _ = try slab.insert(42);
    try testing.expectEqual(@as(usize, 0), index1);
    try testing.expectEqual(@as(usize, 1), slab.next_free);

    const index2, _ = try slab.insert(123);
    try testing.expectEqual(@as(usize, 1), index2);
    try testing.expectEqual(@as(usize, 2), slab.next_free);

    const index3, _ = try slab.insert(999);
    try testing.expectEqual(@as(usize, 2), index3);
    try testing.expectEqual(@as(usize, std.math.maxInt(usize)), slab.next_free);
}

test "CheckedSlab deletion" {
    const allocator = testing.allocator;
    var slab = try CheckedSlab(u32).init(allocator, 3);
    defer slab.deinit();

    _ = try slab.insert(42);
    const index2, _ = try slab.insert(123);
    _ = try slab.insert(999);

    try slab.delete(index2);
    try testing.expectEqual(@as(usize, 1), slab.next_free);

    const index4, _ = try slab.insert(456);
    try testing.expectEqual(@as(usize, 1), index4);
    try testing.expectEqual(@as(usize, std.math.maxInt(usize)), slab.next_free);
}

test "CheckedSlab invalid deletion" {
    const allocator = testing.allocator;
    var slab = try CheckedSlab(u32).init(allocator, 3);
    defer slab.deinit();

    try testing.expectError(error.InvalidIndex, slab.delete(5));
}

test "CheckedSlab expansion" {
    const allocator = testing.allocator;
    var slab = try CheckedSlab(u32).init(allocator, 2);
    defer slab.deinit();

    _ = try slab.insert(42);
    _ = try slab.insert(123);

    try testing.expectEqual(@as(usize, std.math.maxInt(usize)), slab.next_free);

    const index3, _ = try slab.insert(999);
    try testing.expectEqual(@as(usize, 2), index3);
    try testing.expectEqual(@as(usize, 3), slab.data.items.len);
}

test "CheckedSlab reuse after deletion" {
    const allocator = testing.allocator;
    var slab = try CheckedSlab(u32).init(allocator, 3);
    defer slab.deinit();

    const index1, _ = try slab.insert(42);
    const index2, _ = try slab.insert(123);
    _ = try slab.insert(999);

    try slab.delete(index1);
    try slab.delete(index2);

    try testing.expectEqual(@as(usize, 1), slab.next_free);

    const new_index1, _ = try slab.insert(555);
    try testing.expectEqual(@as(usize, 1), new_index1);

    const new_index2, _ = try slab.insert(777);
    try testing.expectEqual(@as(usize, 0), new_index2);
}

test "CheckedSlab with custom struct" {
    const Point = struct {
        x: i32,
        y: i32,
    };

    const allocator = testing.allocator;
    var slab = try CheckedSlab(Point).init(allocator, 2);
    defer slab.deinit();

    const p1 = Point{ .x = 10, .y = 20 };
    const p2 = Point{ .x = 30, .y = 40 };

    const index1, _ = try slab.insert(p1);
    _ = try slab.insert(p2);

    try slab.delete(index1);

    const p3 = Point{ .x = 50, .y = 60 };
    const index3, _ = try slab.insert(p3);

    try testing.expectEqual(@as(usize, 0), index3);
    try testing.expectEqual(@as(i32, 50), p3.x);
    try testing.expectEqual(@as(i32, 60), p3.y);
}
