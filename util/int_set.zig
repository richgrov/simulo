const std = @import("std");

pub fn IntSet(comptime T: type, comptime max_bucket_capacity: usize) type {
    return struct {
        data: []T,
        sizes: []usize,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, starting_buckets: usize) error{OutOfMemory}!Self {
            const data = try allocator.alloc(T, starting_buckets * max_bucket_capacity);
            errdefer allocator.free(data);
            const sizes = try allocator.alloc(usize, starting_buckets);
            errdefer allocator.free(sizes);
            @memset(sizes, 0);

            return Self{
                .data = data,
                .sizes = sizes,
            };
        }

        pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
            allocator.free(self.data);
            allocator.free(self.sizes);
        }

        pub fn put(self: *Self, allocator: std.mem.Allocator, value: T) error{OutOfMemory}!void {
            while (true) {
                const bucket = value % self.sizes.len;
                const index = self.sizes[bucket];

                for (0..index) |i| {
                    if (self.data[bucket * max_bucket_capacity + i] == value) {
                        return;
                    }
                }

                if (index < max_bucket_capacity) {
                    self.data[bucket * max_bucket_capacity + index] = value;
                    self.sizes[bucket] += 1;
                    break;
                }

                const new_data = try allocator.alloc(T, self.data.len * 2);
                errdefer allocator.free(new_data);
                const new_sizes = try allocator.alloc(usize, self.sizes.len * 2);
                errdefer allocator.free(new_sizes);
                @memset(new_sizes, 0);

                for (self.sizes, 0..) |size, old_bucket| {
                    for (0..size) |i| {
                        const item = self.data[old_bucket * max_bucket_capacity + i];
                        const new_bucket = item % new_sizes.len;
                        const bucket_index = new_sizes[new_bucket];
                        new_data[new_bucket * max_bucket_capacity + bucket_index] = item;
                        new_sizes[new_bucket] += 1;
                    }
                }

                allocator.free(self.data);
                allocator.free(self.sizes);
                self.data = new_data;
                self.sizes = new_sizes;
            }
        }

        pub fn delete(self: *Self, value: T) bool {
            const bucket = value % self.sizes.len;
            const bucket_size = self.sizes[bucket];
            for (0..bucket_size) |i| {
                const start = bucket * max_bucket_capacity;
                if (self.data[start + i] != value) {
                    continue;
                }

                self.data[start + i] = self.data[start + bucket_size - 1];
                self.sizes[bucket] -= 1;
                return true;
            }

            return false;
        }

        pub fn clear(self: *Self) void {
            @memset(self.sizes, 0);
        }

        pub fn empty(self: *const Self) bool {
            for (self.sizes) |size| {
                if (size > 0) {
                    return false;
                }
            }

            return true;
        }

        pub fn count(self: *const Self) usize {
            var c: usize = 0;
            for (self.sizes) |size| {
                c += size;
            }
            return c;
        }

        pub fn bucketCount(self: *const Self) usize {
            return self.sizes.len;
        }

        pub fn bucketItems(self: *const Self, index: usize) []const T {
            const bucket_start = index * max_bucket_capacity;
            const bucket_size = self.sizes[index];
            return self.data[bucket_start .. bucket_start + bucket_size];
        }
    };
}

test "IntSet put, iter, delete" {
    const allocator = std.testing.allocator;
    var set = try IntSet(u32, 4).init(allocator, 4);
    defer set.deinit(allocator);

    try std.testing.expectEqual(4, set.bucketCount());

    try set.put(allocator, 5);
    try set.put(allocator, 10);
    try set.put(allocator, 15);
    try set.put(allocator, 20);

    var found = [4]usize{ 0, 0, 0, 0 };
    var count: usize = 0;
    for (0..set.bucketCount()) |bucket_index| {
        const items = set.bucketItems(bucket_index);
        for (items) |item| {
            if (count == 4) {
                @panic(std.fmt.allocPrint(allocator, "extra item {d}", .{item}) catch unreachable);
            }

            switch (item) {
                5 => found[0] += 1,
                10 => found[1] += 1,
                15 => found[2] += 1,
                20 => found[3] += 1,
                else => @panic(std.fmt.allocPrint(allocator, "unexpected item {d}", .{item}) catch unreachable),
            }

            count += 1;
        }
    }

    for (found) |f| {
        try std.testing.expectEqual(1, f);
    }

    try std.testing.expect(set.delete(5));
    try std.testing.expect(set.delete(10));
    try std.testing.expect(set.delete(15));
    try std.testing.expect(set.delete(20));
}

test "IntSet delete non-existent" {
    const allocator = std.testing.allocator;
    var set = try IntSet(u32, 1).init(allocator, 1);
    defer set.deinit(allocator);

    try set.put(allocator, 5);
    try set.put(allocator, 10);
    try set.put(allocator, 15);

    try std.testing.expect(set.delete(10));
    try std.testing.expect(!set.delete(10));
    try std.testing.expect(!set.delete(8));
    try std.testing.expect(set.delete(5));

    var ok = false;
    for (0..set.bucketCount()) |bucket_index| {
        const items = set.bucketItems(bucket_index);
        for (items) |item| {
            if (ok) {
                @panic(std.fmt.allocPrint(allocator, "unexpected item {d}", .{item}) catch unreachable);
            }

            if (item == 15) {
                ok = true;
            }
        }
    }
}

test "IntSet extreme resizing" {
    const allocator = std.testing.allocator;
    var set = try IntSet(u32, 1).init(allocator, 1);
    defer set.deinit(allocator);

    try set.put(allocator, 1);
    try set.put(allocator, 100);
    try set.put(allocator, 50);
    try set.put(allocator, 64);

    var found = [4]usize{ 0, 0, 0, 0 };
    var count: usize = 0;
    for (0..set.bucketCount()) |bucket_index| {
        const items = set.bucketItems(bucket_index);
        for (items) |item| {
            if (count == 4) {
                @panic(std.fmt.allocPrint(allocator, "extra item {d}", .{item}) catch unreachable);
            }

            switch (item) {
                1 => found[0] += 1,
                100 => found[1] += 1,
                50 => found[2] += 1,
                64 => found[3] += 1,
                else => @panic(std.fmt.allocPrint(allocator, "unexpected item {d}", .{item}) catch unreachable),
            }

            count += 1;
        }
    }

    for (found) |f| {
        try std.testing.expectEqual(1, f);
    }
}

test "IntSet empty buckets" {
    const allocator = std.testing.allocator;
    var set = try IntSet(u32, 16).init(allocator, 16);
    defer set.deinit(allocator);

    for (0..set.bucketCount()) |bucket_index| {
        for (set.bucketItems(bucket_index)) |item| {
            @panic(std.fmt.allocPrint(allocator, "unexpected item {d}", .{item}) catch unreachable);
        }
    }
}

test "IntSet put, delete, put" {
    const allocator = std.testing.allocator;
    var set = try IntSet(u32, 16).init(allocator, 4);
    defer set.deinit(allocator);

    try set.put(allocator, 5);
    try set.put(allocator, 10);
    try set.put(allocator, 15);
    try set.put(allocator, 20);
    try std.testing.expect(set.delete(5));
    try std.testing.expect(set.delete(10));
    try std.testing.expect(set.delete(20));
    try set.put(allocator, 5);
    try set.put(allocator, 10);

    var found = [3]usize{ 0, 0, 0 };
    var count: usize = 0;
    for (0..set.bucketCount()) |bucket_index| {
        const items = set.bucketItems(bucket_index);
        for (items) |item| {
            if (count == 3) {
                @panic(std.fmt.allocPrint(allocator, "extra item {d}", .{item}) catch unreachable);
            }

            switch (item) {
                5 => found[0] += 1,
                10 => found[1] += 1,
                15 => found[2] += 1,
                else => @panic(std.fmt.allocPrint(allocator, "unexpected item {d}", .{item}) catch unreachable),
            }

            count += 1;
        }
    }

    for (found) |f| {
        try std.testing.expectEqual(1, f);
    }
}
