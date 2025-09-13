const std = @import("std");

pub fn download(url: []const u8, dest: std.fs.File, allocator: std.mem.Allocator) !usize {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var request = try client.request(.GET, try std.Uri.parse(url), .{});
    defer request.deinit();

    try request.sendBodiless();
    var response = try request.receiveHead(&.{});

    if (response.head.status != .ok) {
        const body = response.reader(&.{});
        var msg_buf: [512]u8 = undefined;
        const msg_len = try body.readSliceShort(&msg_buf);

        std.debug.print("{any}: {s}\n", .{ response.head.status, msg_buf[0..msg_len] });
        return error.DownloadFailed;
    }

    var buf: [1024 * 4]u8 = undefined;
    const body = response.reader(&buf);
    var writer = dest.writer(&.{});
    return try body.streamRemaining(&writer.interface);
}
