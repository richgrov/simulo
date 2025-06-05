const std = @import("std");

pub fn functionParamsIntoTuple(params: []const std.builtin.Type.Fn.Param) type {
    comptime var field_types: [params.len]type = undefined;
    inline for (0..params.len) |i| {
        field_types[i] = params[i].type.?;
    }

    return std.meta.Tuple(&field_types);
}
