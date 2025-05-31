const std = @import("std");
const testing = std.testing;
const Thread = std.Thread;

pub fn Spsc(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        data: [capacity]T,
        head: usize = 0,
        tail: usize = 0,

        pub fn init() Self {
            return Self{
                .data = undefined,
            };
        }

        pub fn enqueue(self: *Self, item: T) !void {
            const insert_at = self.getTail();
            const next_tail = (insert_at + 1) % self.data.len;
            if (next_tail == self.getHead()) {
                return error.QueueFull;
            }

            self.data[insert_at] = item;
            @atomicStore(usize, &self.tail, next_tail, .release);
        }

        pub fn tryDequeue(self: *Self) ?T {
            const read_from = self.getHead();
            if (read_from == self.getTail()) {
                return null;
            }

            const value = self.data[read_from];
            @atomicStore(usize, &self.head, (read_from + 1) % capacity, .release);
            return value;
        }

        fn getHead(self: *Self) usize {
            return @atomicLoad(usize, &self.head, .acquire);
        }

        fn getTail(self: *Self) usize {
            return @atomicLoad(usize, &self.tail, .acquire);
        }
    };
}

test "Sequential balanced" {
    var queue = Spsc(u32, 10).init();

    const Funcs = struct {
        pub fn runEnqueue(q: *Spsc(u32, 10)) void {
            for (0..10000) |i| {
                while (true) {
                    const val: u32 = @intCast(i);
                    q.enqueue(val) catch {
                        continue;
                    };
                    break;
                }
            }
        }

        pub fn runDequeue(q: *Spsc(u32, 10)) void {
            for (0..10000) |i| {
                while (true) {
                    const out = q.tryDequeue() orelse continue;
                    std.testing.expectEqual(i, @as(u32, out)) catch unreachable;
                    break;
                }
            }
        }
    };

    const producer = Thread.spawn(.{}, Funcs.runEnqueue, .{&queue}) catch unreachable;
    const consumer = Thread.spawn(.{}, Funcs.runDequeue, .{&queue}) catch unreachable;
    producer.join();
    consumer.join();
}

test "Sequential write-heavy" {
    var queue = Spsc(u32, 10).init();

    const Funcs = struct {
        pub fn runEnqueue(q: *Spsc(u32, 10)) void {
            for (0..1000) |i| {
                while (true) {
                    const val: u32 = @intCast(i);
                    q.enqueue(val) catch {
                        continue;
                    };
                    break;
                }
            }
        }

        pub fn runDequeue(q: *Spsc(u32, 10)) void {
            for (0..1000) |i| {
                while (true) {
                    const out = q.tryDequeue() orelse continue;
                    std.testing.expectEqual(i, @as(u32, out)) catch unreachable;
                    break;
                }
                std.time.sleep(std.time.ns_per_ms);
            }
        }
    };

    const producer = Thread.spawn(.{}, Funcs.runEnqueue, .{&queue}) catch unreachable;
    const consumer = Thread.spawn(.{}, Funcs.runDequeue, .{&queue}) catch unreachable;
    producer.join();
    consumer.join();
}

test "Sequential read-heavy" {
    var queue = Spsc(u32, 10).init();

    const Funcs = struct {
        pub fn runEnqueue(q: *Spsc(u32, 10)) void {
            for (0..1000) |i| {
                while (true) {
                    const val: u32 = @intCast(i);
                    q.enqueue(val) catch {
                        continue;
                    };
                    break;
                }
                std.time.sleep(std.time.ns_per_ms);
            }
        }

        pub fn runDequeue(q: *Spsc(u32, 10)) void {
            for (0..1000) |i| {
                while (true) {
                    const out = q.tryDequeue() orelse continue;
                    std.testing.expectEqual(i, @as(u32, out)) catch unreachable;
                    break;
                }
            }
        }
    };

    const producer = Thread.spawn(.{}, Funcs.runEnqueue, .{&queue}) catch unreachable;
    const consumer = Thread.spawn(.{}, Funcs.runDequeue, .{&queue}) catch unreachable;
    producer.join();
    consumer.join();
}
