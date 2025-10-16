const std = @import("std");

const util = @import("util");
const FixedArrayList = util.FixedArrayList;

const packet = @import("remote/packet.zig");

var data_dir_buf: [128]u8 = undefined;
var data_dir: ?[]const u8 = null;

pub fn globalInit(allocator: std.mem.Allocator) !void {
    const home_dir = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home_dir);

    data_dir = try std.fmt.bufPrint(&data_dir_buf, "{s}/.simulo", .{home_dir});

    var object_dir_buf: [128]u8 = undefined;
    const object_dir = getFilePath(&object_dir_buf, "objects") catch unreachable;
    try std.fs.cwd().makePath(object_dir);
}

pub fn getFilePath(buf: []u8, name: []const u8) std.fmt.BufPrintError![:0]const u8 {
    return std.fmt.bufPrintZ(buf, "{s}/{s}", .{ data_dir.?, name });
}

pub fn getCachePath(buf: []u8, hash: *const [32]u8) std.fmt.BufPrintError![:0]const u8 {
    const hash_hex = std.fmt.bytesToHex(hash, .lower);
    return std.fmt.bufPrintZ(buf, "{s}/objects/{s}", .{ data_dir.?, hash_hex });
}

pub fn getCachePathAlloc(allocator: std.mem.Allocator, hash: *const [32]u8) std.mem.Allocator.Error![:0]const u8 {
    const hash_hex = std.fmt.bytesToHex(hash, .lower);
    return std.fmt.allocPrintSentinel(allocator, "{s}/objects/{s}", .{ data_dir.?, hash_hex }, 0);
}

pub fn readCachedFile(hash: *const [32]u8, allocator: std.mem.Allocator, max_size: usize) ![]const u8 {
    const hash_hex = std.fmt.bytesToHex(hash, .lower);
    var path_buf: [1024]u8 = undefined;
    const path = getCachePath(&path_buf, hash_hex) catch unreachable;
    return std.fs.readFileAlloc(allocator, path, max_size) catch |err| {
        return err;
    };
}

pub fn storeLatestProgram(program_path: [:0]const u8, assets: []const ProgramAsset) !void {
    var latest_info_buf: [128]u8 = undefined;
    const latest_info_path = getFilePath(&latest_info_buf, "latest") catch unreachable;
    const latest_info = try std.fs.cwd().createFile(latest_info_path, .{});
    defer latest_info.close();

    var writer_struct = latest_info.writer(&.{});
    var writer = &writer_struct.interface;
    try writer.writeAll(&[_]u8{2}); // version
    try writer.writeAll(program_path);
    try writer.writeAll(&[_]u8{0});
    try writer.writeInt(u8, @intCast(assets.len), .big);
    for (assets) |asset| {
        try writer.writeAll(asset.real_path);
        try writer.writeAll(&[_]u8{0});
        const name = asset.name.?;
        try writer.writeInt(u8, @intCast(name.len), .big);
        try writer.writeAll(name.items());
    }
}

pub const max_asset_name_len = 64;

pub const ProgramAsset = struct {
    name: ?FixedArrayList(u8, max_asset_name_len),
    real_path: [:0]const u8,
};

pub const ProgramInfo = struct {
    program_path: [:0]const u8,
    assets: FixedArrayList(ProgramAsset, 16),
};

pub fn loadLatestProgram(allocator: std.mem.Allocator) !?ProgramInfo {
    var latest_info_buf: [128]u8 = undefined;
    const latest_info_path = getFilePath(&latest_info_buf, "latest") catch unreachable;
    const latest_info = std.fs.cwd().openFile(latest_info_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return null;
        }
        return err;
    };
    defer latest_info.close();

    var buf: [32]u8 = undefined;
    var reader_struct = latest_info.reader(&buf);
    var reader = &reader_struct.interface;

    var version: [1]u8 = undefined;
    try reader.readSliceEndian(u8, &version, .big);
    if (version[0] > 2) return error.InvalidVersion;

    const program_path: [:0]const u8 = if (version[0] >= 2) blk: {
        const path = try reader.takeDelimiterInclusive(0);
        break :blk @ptrCast(try allocator.dupe(u8, path));
    } else blk: {
        var program_hash: [32]u8 = undefined;
        try reader.readSliceAll(&program_hash);
        break :blk try getCachePathAlloc(allocator, &program_hash);
    };
    errdefer allocator.free(program_path);

    var num_assets: [1]u8 = undefined;
    try reader.readSliceEndian(u8, &num_assets, .big);
    if (num_assets[0] > 16) return error.InvalidNumAssets;

    var assets = FixedArrayList(ProgramAsset, 16).init();
    for (0..num_assets[0]) |_| {
        const real_path: [:0]const u8 = if (version[0] >= 2) blk: {
            const path = try reader.takeDelimiterInclusive(0);
            break :blk @ptrCast(try allocator.dupe(u8, path));
        } else blk: {
            var hash: [32]u8 = undefined;
            try reader.readSliceAll(&hash);

            break :blk try getCachePathAlloc(allocator, &hash);
        };
        defer allocator.free(real_path);

        var maybe_name: ?FixedArrayList(u8, max_asset_name_len) = null;
        if (version[0] > 0) {
            var name = FixedArrayList(u8, max_asset_name_len).init();

            var asset_name_len: [1]u8 = undefined;
            try reader.readSliceEndian(u8, &asset_name_len, .big);
            if (asset_name_len[0] > max_asset_name_len) return error.AssetNameTooLong;

            name.len = asset_name_len[0];
            try reader.readSliceAll(name.itemsMut());
            maybe_name = name;
        }

        try assets.append(.{
            .name = maybe_name,
            .real_path = real_path,
        });
    }

    return ProgramInfo{
        .program_path = program_path,
        .assets = assets,
    };
}
