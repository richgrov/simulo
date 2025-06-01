const builtin = @import("builtin");

pub const vulkan = builtin.os.tag == .windows or builtin.os.tag == .linux;
