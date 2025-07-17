const std = @import("std");

pub fn download(url: []const u8, dest: std.fs.File, allocator: std.mem.Allocator) !usize {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var body = std.ArrayList(u8).init(allocator);
    defer body.deinit();

    const response = try client.fetch(.{
        .method = .GET,
        .location = .{ .url = url },
        .response_storage = .{
            .dynamic = &body,
        },
    });

    if (response.status != .ok) {
        std.debug.print("{any}: {s}\n", .{ response.status, body.items });
        return error.DownloadFailed;
    }

    try dest.writeAll(body.items);
    return body.items.len;
}
