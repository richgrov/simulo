const builtin = @import("builtin");
const std = @import("std");

const EventType = switch (builtin.target.os.tag) {
    .macos => @import("event_loop_macos.zig").EventType,
    .linux => @import("event_loop_linux.zig").EventType,
    else => @compileError("Unsupported platform for EventLoop"),
};

pub const EventLoop = switch (builtin.target.os.tag) {
    .macos => @import("event_loop_macos.zig").EventLoop,
    .linux => @import("event_loop_linux.zig").EventLoop,
    else => @compileError("Unsupported platform for EventLoop"),
};

test "EventLoop file reading" {
    const allocator = std.testing.allocator;
    const expected_content = "Hello, World!\nThis is a test file for the EventLoop implementation.\nIt contains multiple lines of text to test reading functionality.";

    var loop = try EventLoop.init(allocator);
    defer loop.deinit();

    var events = try std.ArrayList(EventType).initCapacity(allocator, 64);
    defer events.deinit(allocator);

    var test_buffer: [16]u8 = undefined;
    var received_content = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer received_content.deinit(allocator);

    try loop.openFile("runtime/io/test.txt", &events, EventLoop.OpenMode.read_only);

    var open_retries: usize = 0;
    while (events.items.len == 0 and open_retries < 100) : (open_retries += 1) {
        try loop.poll();
        if (events.items.len == 0) std.Thread.sleep(1 * std.time.ns_per_ms);
    }

    if (events.items.len != 1) {
        std.debug.print("Failed to receive open event after {} retries. Events len: {}\n", .{ open_retries, events.items.len });
        return error.TestFailed;
    }

    const open_event = events.items[0];
    if (open_event == .err) {
        std.debug.print("Open failed: {}\n", .{open_event.err.error_code});
        return error.TestFailed;
    }
    try std.testing.expect(open_event.open_complete.fd >= 0);

    const fd = open_event.open_complete.fd;

    try loop.startReadFile(fd, &test_buffer, &events);

    var total_bytes: usize = 0;
    var found_complete = false;

    var loops: usize = 0;
    while (!found_complete and loops < 100) {
        loops += 1;

        events.clearRetainingCapacity();

        try loop.poll();

        if (events.items.len == 0) {
            std.debug.print("Poll returned 0 events (loop {})\n", .{loops});
            std.Thread.sleep(10 * std.time.ns_per_ms);
            continue;
        }

        for (events.items) |event| {
            switch (event) {
                .read_complete => |read_event| {
                    if (read_event.bytes_read == 0) {
                        found_complete = true; // End of file detected
                        loop.closeFile(read_event.fd);
                    } else {
                        total_bytes += read_event.bytes_read;
                        try received_content.appendSlice(allocator, read_event.data);
                    }
                },
                .err => |err_event| {
                    std.debug.print("Error during test: {}\n", .{err_event.error_code});
                    try std.testing.expect(false); // Should not have errors
                },
                else => {}, // Ignore other event types
            }
        }
    }

    if (!found_complete) {
        std.debug.print("Failed to find EOF after {} loops. Total bytes: {}\n", .{ loops, total_bytes });
    }

    // Verify we read data and detected end of file
    try std.testing.expect(total_bytes > 0);
    try std.testing.expect(found_complete);

    // Verify content matches
    try std.testing.expectEqualSlices(u8, expected_content, received_content.items);
}

test "EventLoop file writing" {
    const allocator = std.testing.allocator;
    const test_content = "Hello, EventLoop Write!";
    const test_filename = "runtime/io/test_write.txt";

    // Create/Truncate file for writing
    const file = try std.fs.cwd().createFile(test_filename, .{ .read = true });
    file.close();

    var loop = try EventLoop.init(allocator);
    defer loop.deinit();

    var events = try std.ArrayList(EventType).initCapacity(allocator, 64);
    defer events.deinit(allocator);

    try loop.openFile(test_filename, &events, EventLoop.OpenMode.read_write);

    var open_retries: usize = 0;
    while (events.items.len == 0 and open_retries < 100) : (open_retries += 1) {
        try loop.poll();
        if (events.items.len == 0) std.Thread.sleep(1 * std.time.ns_per_ms);
    }

    if (events.items.len != 1) {
        std.debug.print("Failed to receive open event after {} retries. Events len: {}\n", .{ open_retries, events.items.len });
        return error.TestFailed;
    }

    const open_event = events.items[0];
    if (open_event == .err) {
        std.debug.print("Open failed: {}\n", .{open_event.err.error_code});
        return error.TestFailed;
    }

    const fd = open_event.open_complete.fd;
    defer loop.closeFile(fd);

    try loop.startWriteFile(fd, test_content, &events);

    var total_bytes_written: usize = 0;
    var write_complete = false;

    var loops: usize = 0;
    while (!write_complete and loops < 100) {
        loops += 1;
        events.clearRetainingCapacity();
        try loop.poll();

        if (events.items.len == 0) {
            std.Thread.sleep(1 * std.time.ns_per_ms);
            continue;
        }

        for (events.items) |event| {
            switch (event) {
                .write_complete => |write_event| {
                    total_bytes_written += write_event.bytes_written;
                    if (total_bytes_written >= test_content.len) {
                        write_complete = true;
                    }
                },
                .err => |err_event| {
                    std.debug.print("Error during write test: {}\n", .{err_event.error_code});
                    return error.TestFailed;
                },
                else => {},
            }
        }
    }

    try std.testing.expect(write_complete);
    try std.testing.expectEqual(test_content.len, total_bytes_written);

    // Verify content
    const read_content = try std.fs.cwd().readFileAlloc(allocator, test_filename, 1024);
    defer allocator.free(read_content);
    try std.testing.expectEqualSlices(u8, test_content, read_content);

    try std.fs.cwd().deleteFile(test_filename);
}

test "EventLoop TCP connection" {
    const allocator = std.testing.allocator;
    const port = 9001;

    // Start python server
    const args = [_][]const u8{ "python3", "runtime/io/test_tcp.py", "9001" };
    var child = std.process.Child.init(&args, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    try child.spawn();

    // Give it a moment to start
    std.Thread.sleep(500 * std.time.ns_per_ms);

    defer {
        _ = child.kill() catch {};
        _ = child.wait() catch {};
    }

    var loop = try EventLoop.init(allocator);
    defer loop.deinit();

    var events = try std.ArrayList(EventType).initCapacity(allocator, 64);
    defer events.deinit(allocator);

    const address = try std.net.Address.parseIp("127.0.0.1", port);

    try loop.connectTcp(address, &events);

    var connected = false;
    var fd: std.c.fd_t = -1;

    // Wait for connection
    var loops: usize = 0;
    while (!connected and loops < 100) {
        loops += 1;
        events.clearRetainingCapacity();
        try loop.poll();

        if (events.items.len == 0) {
            std.Thread.sleep(10 * std.time.ns_per_ms);
            continue;
        }

        for (events.items) |event| {
            switch (event) {
                .connect_complete => |ev| {
                    connected = true;
                    fd = ev.fd;
                },
                .err => |err| {
                    std.debug.print("Connect error: {}\n", .{err.error_code});
                    return error.TestFailed;
                },
                else => {},
            }
        }
    }
    try std.testing.expect(connected);
    defer loop.closeFile(fd);

    // Write data
    const message = "Hello Server";
    try loop.startWriteFile(fd, message, &events);

    var write_complete = false;
    loops = 0;
    while (!write_complete and loops < 100) {
        loops += 1;
        events.clearRetainingCapacity();
        try loop.poll();

        for (events.items) |event| {
            switch (event) {
                .write_complete => |ev| {
                    if (ev.bytes_written == message.len) write_complete = true;
                },
                .err => return error.TestFailed,
                else => {},
            }
        }
        if (!write_complete) std.Thread.sleep(10 * std.time.ns_per_ms);
    }
    try std.testing.expect(write_complete);

    // Read response
    var read_buffer: [1024]u8 = undefined;
    var response = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer response.deinit(allocator);

    try loop.startReadSocket(fd, &read_buffer, &events);

    var read_complete = false;
    loops = 0;
    while (!read_complete and loops < 100) {
        loops += 1;
        events.clearRetainingCapacity();
        try loop.poll();

        for (events.items) |event| {
            switch (event) {
                .read_complete => |ev| {
                    if (ev.bytes_read > 0) {
                        try response.appendSlice(allocator, ev.data);
                        if (std.mem.indexOf(u8, response.items, "Ack: Hello Server") != null) {
                            read_complete = true;
                        }
                    } else {
                        // EOF or 0 read
                        read_complete = true;
                    }
                },
                .err => return error.TestFailed,
                else => {},
            }
        }
        if (!read_complete) std.Thread.sleep(10 * std.time.ns_per_ms);
    }

    try std.testing.expect(std.mem.indexOf(u8, response.items, "Ack: Hello Server") != null);
}

test "EventLoop timer" {
    const allocator = std.testing.allocator;
    var loop = try EventLoop.init(allocator);
    defer loop.deinit();

    var events = try std.ArrayList(EventType).initCapacity(allocator, 64);
    defer events.deinit(allocator);

    // Start a 10ms timer
    try loop.startTimer(10, 12345, &events);

    var timer_fired = false;
    var loops: usize = 0;
    while (!timer_fired and loops < 100) {
        loops += 1;
        events.clearRetainingCapacity();
        try loop.poll();

        for (events.items) |event| {
            switch (event) {
                .timer_complete => |ev| {
                    if (ev.id == 12345) timer_fired = true;
                },
                .err => return error.TestFailed,
                else => {},
            }
        }
        if (!timer_fired) std.Thread.sleep(1 * std.time.ns_per_ms);
    }

    try std.testing.expect(timer_fired);
}

test "EventLoop file async close" {
    const allocator = std.testing.allocator;
    const test_filename = "runtime/io/test_async_close.txt";

    // Create a dummy file
    const file = try std.fs.cwd().createFile(test_filename, .{ .read = true });
    file.close();
    defer std.fs.cwd().deleteFile(test_filename) catch {};

    var loop = try EventLoop.init(allocator);
    defer loop.deinit();

    var events = try std.ArrayList(EventType).initCapacity(allocator, 64);
    defer events.deinit(allocator);

    // Open file first
    try loop.openFile(test_filename, &events, EventLoop.OpenMode.read_only);

    var open_retries: usize = 0;
    while (events.items.len == 0 and open_retries < 100) : (open_retries += 1) {
        try loop.poll();
        if (events.items.len == 0) std.Thread.sleep(1 * std.time.ns_per_ms);
    }

    if (events.items.len != 1) return error.TestFailed;
    const open_event = events.items[0];
    const fd = open_event.open_complete.fd;

    // Now async close
    events.clearRetainingCapacity();
    try loop.startCloseFile(fd, &events);

    var close_retries: usize = 0;
    var closed = false;

    // Check for immediate completion (macOS/Synchronous)
    for (events.items) |event| {
        switch (event) {
            .close_complete => |ev| {
                if (ev.fd == fd) closed = true;
            },
            .err => |err| {
                std.debug.print("Close error: {}\n", .{err.error_code});
                return error.TestFailed;
            },
            else => {},
        }
    }

    while (!closed and close_retries < 100) : (close_retries += 1) {
        events.clearRetainingCapacity();
        try loop.poll();

        for (events.items) |event| {
            switch (event) {
                .close_complete => |ev| {
                    if (ev.fd == fd) closed = true;
                },
                .err => |err| {
                    std.debug.print("Close error: {}\n", .{err.error_code});
                    return error.TestFailed;
                },
                else => {},
            }
        }
        if (!closed) std.Thread.sleep(1 * std.time.ns_per_ms);
    }

    try std.testing.expect(closed);
}
