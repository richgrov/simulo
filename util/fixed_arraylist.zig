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
