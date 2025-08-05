const std = @import("std");

const util = @import("util");

const Runtime = @import("runtime.zig").Runtime;
const Renderer = @import("render/renderer.zig").Renderer;
const Detection = @import("inference/inference.zig").Detection;

const MASK_WIDTH = 100.0;
const MASK_HEIGHT = 50.0;

const MaskData = struct {
    left_id: usize,
    right_id: usize,
};

pub const EyeGuard = struct {
    mask_material: Renderer.MaterialHandle,
    masks: std.AutoHashMap(u64, MaskData),

    pub fn init(allocator: std.mem.Allocator, renderer: *Renderer, white_pixel_texture: Renderer.ImageHandle) !EyeGuard {
        return .{
            .mask_material = try renderer.createUiMaterial(white_pixel_texture, 0.0, 0.0, 0.0),
            .masks = std.AutoHashMap(u64, MaskData).init(allocator),
        };
    }

    pub fn deinit(self: *EyeGuard) void {
        self.masks.deinit();
    }

    pub fn handleEvent(self: *EyeGuard, id: u64, det: *const Detection, runtime: *Runtime, window_width: f32, window_height: f32) void {
        const l_eye = det.keypoints[1];
        const r_eye = det.keypoints[2];
        const lx = l_eye.pos[0] * window_width;
        const ly = l_eye.pos[1] * window_height;
        const rx = r_eye.pos[0] * window_width;
        const ry = r_eye.pos[1] * window_height;

        if (self.masks.get(id)) |mask_data| {
            _ = self.updateMaskObject(runtime, mask_data.left_id, lx, ly);
            _ = self.updateMaskObject(runtime, mask_data.right_id, rx, ry);
        } else {
            const left_id = self.updateMaskObject(runtime, null, lx, ly);
            const right_id = self.updateMaskObject(runtime, null, rx, ry);
            self.masks.put(id, .{ .left_id = left_id, .right_id = right_id }) catch |err| util.crash.oom(err);
        }
    }

    pub fn handleDelete(self: *EyeGuard, runtime: *Runtime, id: u64) void {
        if (self.masks.get(id)) |mask_data| {
            runtime.deleteObject(mask_data.left_id);
            runtime.deleteObject(mask_data.right_id);
            std.debug.assert(self.masks.remove(id));
        }
    }

    fn updateMaskObject(self: *EyeGuard, runtime: *Runtime, object_id: ?usize, x: f32, y: f32) usize {
        const spawn_x = x - MASK_WIDTH / 2.0;
        const spawn_y = y - MASK_HEIGHT / 3.0;

        if (object_id) |mask_obj_id| {
            const mask_obj = runtime.getObject(mask_obj_id).?;
            mask_obj.pos = .{ spawn_x, spawn_y, 0.0 };
            runtime.markOutdatedTransform(mask_obj_id);
            return mask_obj_id;
        }

        const obj_id = runtime.createObject(spawn_x, spawn_y, self.mask_material, true);
        const mask_obj = runtime.getObject(obj_id).?;
        mask_obj.scale = .{ MASK_WIDTH, MASK_HEIGHT, 1.0 };
        runtime.markOutdatedTransform(obj_id);
        return obj_id;
    }
};
