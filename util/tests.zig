const std = @import("std");

test "load containers" {
    _ = @import("fixed_arraylist.zig");
    _ = @import("fixed_slab.zig");
    _ = @import("packed_set.zig");
    _ = @import("spsc_ring.zig");
}
