pub fn FixedArrayList(comptime T: type, comptime capacity: usize) type {
    return struct {
        data: [capacity]T = undefined,
        len: usize = 0,

        const Self = @This();

        pub fn init() Self {
            return .{};
        }

        pub fn append(self: *Self, item: T) !void {
            if (self.len == capacity) return error.OutOfMemory;
            self.data[self.len] = item;
            self.len += 1;
        }

        pub fn get(self: *Self, index: usize) ?T {
            if (index >= self.len) return null;
            return self.data[index];
        }

        pub fn items(self: *Self) []const T {
            return self.data[0..self.len];
        }
    };
}
