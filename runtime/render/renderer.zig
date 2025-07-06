const std = @import("std");
const builtin = @import("builtin");

const ffi = @cImport({
    @cInclude("ffi.h");
});

const Gpu = @import("../gpu/gpu.zig").Gpu;
const Window = @import("../window/window.zig").Window;
const Mat4 = @import("engine").math.Mat4;

pub const Renderer = struct {
    handle: *ffi.Renderer,
    materials: std.ArrayList(MaterialHandle),

    pub const PipelineHandle = struct { id: u32 };
    pub const MaterialHandle = struct { id: u32 };
    pub const MeshHandle = struct { id: u32 };
    pub const ObjectHandle = struct { id: u32 };
    pub const ImageHandle = struct { id: u32 };

    pub fn init(gpu: *const Gpu, window: *const Window, allocator: std.mem.Allocator) !Renderer {
        const renderer = ffi.create_renderer(gpu.handle, window.handle).?;
        errdefer ffi.destroy_renderer(renderer);

        return Renderer{
            .handle = renderer,
            .materials = try std.ArrayList(MaterialHandle).initCapacity(allocator, 64),
        };
    }

    pub fn deinit(self: *Renderer) void {
        ffi.destroy_renderer(self.handle);
    }

    pub fn createUiMaterial(self: *Renderer, image: ImageHandle, r: f32, g: f32, b: f32) !MaterialHandle {
        const id = ffi.create_ui_material(self.handle, image.id, r, g, b);
        const handle = MaterialHandle{ .id = id };
        try self.materials.append(handle);
        return handle;
    }

    pub fn createMeshMaterial(self: *Renderer, r: f32, g: f32, b: f32) !MaterialHandle {
        const id = ffi.create_mesh_material(self.handle, r, g, b);
        const handle = MaterialHandle{ .id = id };
        try self.materials.append(handle);
        return handle;
    }

    pub fn createMesh(self: *Renderer, vertices: []const u8, indices: []const u16) MeshHandle {
        const id = ffi.create_mesh(self.handle, @constCast(@ptrCast(vertices.ptr)), vertices.len, @constCast(@ptrCast(indices.ptr)), indices.len);
        return MeshHandle{ .id = id };
    }

    pub fn deleteMesh(self: *Renderer, mesh: MeshHandle) void {
        ffi.delete_mesh(self.handle, mesh.id);
    }

    pub fn addObject(self: *Renderer, mesh: MeshHandle, transform: Mat4, material: MaterialHandle) ObjectHandle {
        const id = ffi.add_object(self.handle, mesh.id, transform.ptr(), material.id);
        return ObjectHandle{ .id = id };
    }

    pub fn setObjectTransform(self: *Renderer, object: ObjectHandle, transform: Mat4) void {
        ffi.set_object_transform(self.handle, object.id, transform.ptr());
    }

    pub fn deleteObject(self: *Renderer, object: ObjectHandle) void {
        ffi.delete_object(self.handle, object.id);
    }

    pub fn createImage(self: *Renderer, image_data: []const u8, width: i32, height: i32) ImageHandle {
        const id = ffi.create_image(self.handle, @constCast(@ptrCast(image_data.ptr)), width, height);
        return ImageHandle{ .id = id };
    }

    pub fn render(self: *Renderer, window: *const Window, ui_view_projection: *const Mat4, world_view_projection: *const Mat4) !void {
        if (comptime builtin.os.tag == .macos) {
            self.renderMetal(ui_view_projection, world_view_projection);
        } else {
            try self.renderVulkan(window, ui_view_projection, world_view_projection);
        }
    }

    fn renderMetal(self: *Renderer, ui_view_projection: *const Mat4, world_view_projection: *const Mat4) void {
        _ = world_view_projection;

        if (!ffi.begin_render(self.handle)) {
            return;
        }

        ffi.set_pipeline(self.handle, 0); // pipeline id not currently used

        for (self.materials.items) |material| {
            ffi.render_material(self.handle, material.id, ui_view_projection.ptr());
        }

        if (self.mask_material) |mask_material| {
            ffi.render_material(self.handle, mask_material.id, ui_view_projection.ptr());
        }

        ffi.end_render(self.handle);
    }

    fn renderVulkan(self: *Renderer, window: *const Window, ui_view_projection: *const Mat4, world_view_projection: *const Mat4) !void {
        const ok = ffi.render(self.handle, ui_view_projection.ptr(), world_view_projection.ptr());
        if (!ok) {
            ffi.recreate_swapchain(self.handle, window.handle);

            if (!ffi.render(self.handle, ui_view_projection.ptr(), world_view_projection.ptr())) {
                return error.RenderFailed;
            }
        }
    }

    pub fn waitIdle(self: *Renderer) void {
        ffi.wait_idle(self.handle);
    }
};
