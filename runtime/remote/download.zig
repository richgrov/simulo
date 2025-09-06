const std = @import("std");

pub fn download(url: []const u8, dest: std.fs.File, allocator: std.mem.Allocator) !usize {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var body: [1024]u8 = undefined;
    var body_writer = std.io.Writer.fixed(&body);

    const response = try client.fetch(.{
        .method = .GET,
        .location = .{ .url = url },
        .response_writer = &body_writer,
    });

    if (response.status != .ok) {
        std.debug.print("{any}: {s}\n", .{ response.status, body[0..body_writer.end] });
        return error.DownloadFailed;
    }

    try dest.writeAll(body[0..body_writer.end]);
    return body_writer.end;
}
