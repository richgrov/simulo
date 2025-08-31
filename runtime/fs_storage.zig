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

pub fn readCachedFile(hash: *const [32]u8, allocator: std.mem.Allocator, max_size: usize) ![]const u8 {
    const hash_hex = std.fmt.bytesToHex(hash, .lower);
    var path_buf: [1024]u8 = undefined;
    const path = getCachePath(&path_buf, hash_hex) catch unreachable;
    return std.fs.readFileAlloc(allocator, path, max_size) catch |err| {
        return err;
    };
}

pub fn storeLatestProgram(program_hash: *const [32]u8, assets: []const ProgramAsset) !void {
    var latest_info_buf: [128]u8 = undefined;
    const latest_info_path = getFilePath(&latest_info_buf, "latest") catch unreachable;
    const latest_info = try std.fs.cwd().createFile(latest_info_path, .{});
    defer latest_info.close();

    const writer = latest_info.writer();
    try writer.writeAll(&[_]u8{1}); // version
    try writer.writeAll(program_hash);
    try writer.writeInt(u8, @intCast(assets.len), .big);
    for (assets) |asset| {
        try writer.writeAll(&asset.hash);
        const name = asset.name.?;
        try writer.writeInt(u8, @intCast(name.len), .big);
        try writer.writeAll(name.items());
    }
}

pub const max_asset_name_len = 64;

pub const ProgramAsset = struct {
    name: ?FixedArrayList(u8, max_asset_name_len),
    hash: [32]u8,
};

pub const ProgramInfo = struct {
    program_hash: [32]u8,
    assets: FixedArrayList(ProgramAsset, 16),
};

pub fn loadLatestProgram() !?ProgramInfo {
    var latest_info_buf: [128]u8 = undefined;
    const latest_info_path = getFilePath(&latest_info_buf, "latest") catch unreachable;
    const latest_info = std.fs.cwd().openFile(latest_info_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return null;
        }
        return err;
    };
    defer latest_info.close();

    const reader = latest_info.reader();

    const version = try reader.readInt(u8, .big);
    if (version > 1) return error.InvalidVersion;

    var program_hash: [32]u8 = undefined;
    try reader.readNoEof(&program_hash);

    const num_assets = try reader.readInt(u8, .big);
    if (num_assets > 16) return error.InvalidNumAssets;

    var assets = FixedArrayList(ProgramAsset, 16).init();
    for (0..num_assets) |_| {
        var hash: [32]u8 = undefined;
        try reader.readNoEof(&hash);

        var maybe_name: ?FixedArrayList(u8, max_asset_name_len) = null;
        if (version > 0) {
            var name = FixedArrayList(u8, max_asset_name_len).init();
            const asset_name_len = try reader.readInt(u8, .big);
            if (asset_name_len > max_asset_name_len) return error.AssetNameTooLong;
            name.len = asset_name_len;
            try reader.readNoEof(name.items());
            maybe_name = name;
        }

        try assets.append(.{
            .name = maybe_name,
            .hash = hash,
        });
    }

    return ProgramInfo{
        .program_hash = program_hash,
        .asset_hashes = assets,
    };
}
