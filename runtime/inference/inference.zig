const builtin = @import("builtin");

pub usingnamespace if (builtin.os.tag == .linux)
    @import("tensorrt_rtx.zig")
else
    @import("onnx.zig");
