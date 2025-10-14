const std = @import("std");

const engine = @import("engine");
const Mat4 = engine.math.Mat4;

const util = @import("util");

const Runtime = @import("runtime.zig").Runtime;
const Renderer = @import("render/renderer.zig").Renderer;
const Detection = @import("inference/inference.zig").Detection;

const MASK_WIDTH = 100.0;
const MASK_HEIGHT = 50.0;

const MaskData = struct {
    left_id: Renderer.ObjectHandle,
    right_id: Renderer.ObjectHandle,
};

pub const EyeGuard = struct {
    mesh: Renderer.MeshHandle,
    mask_material: Renderer.MaterialHandle,
    masks: std.AutoHashMap(u64, MaskData),

    pub fn init(allocator: std.mem.Allocator, renderer: *Renderer, mesh: Renderer.MeshHandle, white_pixel_texture: Renderer.ImageHandle) !EyeGuard {
        return .{
            .mask_material = try renderer.createUiMaterial(white_pixel_texture, 0.0, 0.0, 0.0),
            .mesh = mesh,
            .masks = std.AutoHashMap(u64, MaskData).init(allocator),
        };
    }

    pub fn deinit(self: *EyeGuard) void {
        self.masks.deinit();
    }

    pub fn handleEvent(self: *EyeGuard, id: u64, det: *const Detection, renderer: *Renderer, window_width: f32, window_height: f32) void {
        const l_eye = det.keypoints[1];
        const r_eye = det.keypoints[2];
        const lx = l_eye.pos[0] * window_width;
        const ly = l_eye.pos[1] * window_height;
        const rx = r_eye.pos[0] * window_width;
        const ry = r_eye.pos[1] * window_height;

        if (self.masks.get(id)) |mask_data| {
            _ = self.updateMaskObject(renderer, mask_data.left_id, lx, ly);
            _ = self.updateMaskObject(renderer, mask_data.right_id, rx, ry);
        } else {
            const left_id = self.updateMaskObject(renderer, null, lx, ly);
            const right_id = self.updateMaskObject(renderer, null, rx, ry);
            self.masks.put(id, .{ .left_id = left_id, .right_id = right_id }) catch |err| util.crash.oom(err);
        }
    }

    pub fn handleDelete(self: *EyeGuard, renderer: *Renderer, id: u64) void {
        if (self.masks.get(id)) |mask_data| {
            renderer.deleteObject(mask_data.left_id);
            renderer.deleteObject(mask_data.right_id);
            std.debug.assert(self.masks.remove(id));
        }
    }

    fn updateMaskObject(self: *EyeGuard, renderer: *Renderer, object_id: ?Renderer.ObjectHandle, x: f32, y: f32) Renderer.ObjectHandle {
        const spawn_x = x - MASK_WIDTH / 2.0;
        const spawn_y = y - MASK_HEIGHT / 3.0;

        const translate = Mat4.translate(.{ spawn_x, spawn_y, 0.0 });
        const scale = Mat4.scale(.{ MASK_WIDTH, MASK_HEIGHT, 1.0 });
        const transform = translate.matmul(&scale);

        if (object_id) |mask_obj_id| {
            renderer.setObjectTransform(mask_obj_id, transform);
            return mask_obj_id;
        }

        return renderer.addObject(self.mesh, transform, self.mask_material, 31) catch |err| util.crash.oom(err);
    }
};
