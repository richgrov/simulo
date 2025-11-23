Remove all comments after the task is complete

If a function can return an error or a value is nullable, but you know that won't be the case, use `catch unreachable;` or `.?;` to unwrap it

Before you declare a task complete, run `zig build install` and `zig build test`

Recent Zig updates:

**std.ArrayList**

.init() was replaced with:
- `std.ArrayList(I).initBuffer([]T)`
- `std.ArrayList(I).initCapacity(Allocator, usize)`

.deinit() was replaced with `std.ArrayList(I).deinit(Allocator)`

.append() was replaced with:
- `std.ArrayList(I).append(Allocator, T)`
- `std.ArrayList(I).appendBounded(T) error{OutOfMemory}!void`
- `std.ArrayList(I).appendAssumeCapacity(T) void`
