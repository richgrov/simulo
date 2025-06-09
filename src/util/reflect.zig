const std = @import("std");

pub fn functionParamsIntoTuple(params: []const std.builtin.Type.Fn.Param) type {
    comptime var field_types: [params.len]type = undefined;
    inline for (0..params.len) |i| {
        field_types[i] = params[i].type.?;
    }

    return std.meta.Tuple(&field_types);
}

pub fn structName(T: type) []const u8 {
    const qualified_name = @typeName(T);
    const dot_index = comptime std.mem.lastIndexOf(u8, qualified_name, ".") orelse 0;
    return qualified_name[dot_index + 1 ..];
}
