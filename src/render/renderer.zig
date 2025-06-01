const std = @import("std");

const ffi = @cImport({
    @cInclude("ffi.h");
});

const Gpu = @import("../gpu/gpu.zig").Gpu;
const Window = @import("../window/window.zig").Window;
const Mat4 = @import("../math/matrix.zig").Mat4;

pub const PipelineHandle = struct { id: u32 };
pub const MaterialHandle = struct { id: u32 };
pub const MeshHandle = struct { id: u32 };
pub const ObjectHandle = struct { id: u32 };
pub const ImageHandle = struct { id: u32 };

pub const Renderer = struct {
    handle: *ffi.Renderer,

    pub fn init(gpu: *const Gpu, window: *const Window) Renderer {
        return Renderer{
            .handle = ffi.create_renderer(gpu.handle, window.handle).?,
        };
    }

    pub fn deinit(self: *Renderer) void {
        ffi.destroy_renderer(self.handle);
    }

    pub fn createUiMaterial(self: *Renderer, image: ImageHandle, r: f32, g: f32, b: f32) MaterialHandle {
        const id = ffi.create_ui_material(self.handle, image.id, r, g, b);
        return MaterialHandle{ .id = id };
    }

    pub fn createMeshMaterial(self: *Renderer, r: f32, g: f32, b: f32) MaterialHandle {
        const id = ffi.create_mesh_material(self.handle, r, g, b);
        return MaterialHandle{ .id = id };
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

    pub fn render(self: *Renderer, ui_view_projection: *const Mat4, world_view_projection: *const Mat4) bool {
        return ffi.render(self.handle, ui_view_projection.ptr(), world_view_projection.ptr());
    }

    pub fn recreateSwapchain(self: *Renderer) void {
        ffi.recreate_swapchain(self.handle);
    }

    pub fn waitIdle(self: *Renderer) void {
        ffi.wait_idle(self.handle);
    }
};
