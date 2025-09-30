const std = @import("std");

const util = @import("util");

const inference = @import("inference.zig");
const Box = inference.Box;
const Detection = inference.Detection;

const TrackedBox = struct {
    box: Box,
    id: u32,
};

pub const TrackingEvent = union(enum) {
    moved: struct { id: u32, new_box: usize },
    lost: u32,
};

const MAX_OBJECTS = 128;

pub const BoxTracker = struct {
    prev_boxes: util.FixedArrayList(TrackedBox, MAX_OBJECTS),
    next_tracking_id: u32 = 0,
    // capacity is doubled for the worst-case scenario of all objects from the previous frame being lost and all objects from the current frame being new
    events: util.FixedArrayList(TrackingEvent, MAX_OBJECTS * 2),

    pub fn init() BoxTracker {
        return BoxTracker{
            .prev_boxes = util.FixedArrayList(TrackedBox, MAX_OBJECTS).init(),
            .next_tracking_id = 0,
            .events = util.FixedArrayList(TrackingEvent, MAX_OBJECTS * 2).init(),
        };
    }

    pub fn update(self: *BoxTracker, detections: []const Detection) []const TrackingEvent {
        self.events.len = 0;

        const prev_frame_boxes = self.prev_boxes.len;
        const association = associateBoxes(detections, self.prev_boxes.items());

        for (0..detections.len) |i| {
            if (association.new2prev[i]) |prev_idx| {
                const prev = &self.prev_boxes.itemsMut()[prev_idx];
                prev.box = detections[i].box;
                self.events.append(.{ .moved = .{ .id = prev.id, .new_box = i } }) catch unreachable;
            } else {
                const id = self.next_tracking_id;
                self.next_tracking_id += 1;
                self.prev_boxes.append(.{ .id = id, .box = detections[i].box }) catch unreachable;
                self.events.append(.{ .moved = .{ .id = id, .new_box = i } }) catch unreachable;
            }
        }

        // loop backwards to preserve ordering of boxes as they are deleted
        var i: usize = prev_frame_boxes;
        while (i > 0) {
            i -= 1;

            if (association.prev_survived[i]) {
                continue;
            }
            const id = self.prev_boxes.items()[i].id;
            self.events.append(.{ .lost = id }) catch unreachable;
            self.prev_boxes.swapDelete(@intCast(i)) catch unreachable;
        }

        return self.events.items();
    }
};

const AssociateResult = struct {
    new2prev: [MAX_OBJECTS]?usize = .{null} ** MAX_OBJECTS,
    prev_survived: [MAX_OBJECTS]bool = .{false} ** MAX_OBJECTS,
};

fn associateBoxes(new: []const Detection, prev: []const TrackedBox) AssociateResult {
    const Movement = struct {
        new_idx: usize,
        prev_idx: usize,
        distance: f32,

        const Self = @This();

        fn lessThan(_: void, a_cmp: Self, b_cmp: Self) bool {
            return a_cmp.distance < b_cmp.distance;
        }
    };

    var distance_buf: [MAX_OBJECTS * MAX_OBJECTS]Movement = undefined;
    var distances = std.ArrayList(Movement).initBuffer(&distance_buf);
    for (new, 0..) |*new_detection, a_idx| {
        for (prev, 0..) |*prev_tracked, b_idx| {
            const diff = prev_tracked.box.pos - new_detection.box.pos;
            const distance = diff[0] * diff[0] + diff[1] * diff[1];
            distances.appendAssumeCapacity(.{
                .new_idx = a_idx,
                .prev_idx = b_idx,
                .distance = distance,
            });
        }
    }

    std.mem.sortUnstable(Movement, distances.items, {}, Movement.lessThan);

    var result = AssociateResult{};

    var i: usize = 0;
    var remaining_a = new.len;
    while (i < distances.items.len and remaining_a > 0) : (i += 1) {
        const movement = distances.items[i];
        if (result.new2prev[movement.new_idx] != null or result.prev_survived[movement.prev_idx]) {
            continue;
        }

        result.new2prev[movement.new_idx] = movement.prev_idx;
        result.prev_survived[movement.prev_idx] = true;
        remaining_a -= 1;
    }

    return result;
}
