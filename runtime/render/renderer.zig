const std = @import("std");
const builtin = @import("builtin");

const ffi = @cImport({
    @cInclude("ffi.h");
});

const Gpu = @import("../gpu/gpu.zig").Gpu;
const Window = @import("../window/window.zig").Window;
const Mat4 = @import("engine").math.Mat4;
const FixedArrayList = @import("util").FixedArrayList;
const FixedSlab = @import("util").FixedSlab;
const SparseIntSet = @import("util").SparseIntSet;

const MAX_RENDER_LAYERS = 32;
const MAX_MATERIALS = 512;
const MAX_MESHES = 2048;
const MAX_MESH_PASSES = 256;

const MaterialPass = struct {
    mesh_passes: SparseIntSet(u32, MAX_MESH_PASSES) = .{},
};

const RenderCollection = struct {
    material_passes: std.AutoHashMap(u16, u16),

    pub fn init(allocator: std.mem.Allocator) RenderCollection {
        return RenderCollection{
            .material_passes = std.AutoHashMap(u16, u16).init(allocator),
        };
    }
};

pub const Renderer = struct {
    handle: *ffi.Renderer,
    meshes: FixedSlab(u32, MAX_MESHES),
    materials: FixedSlab(u32, MAX_MATERIALS),
    material_passes: FixedSlab(MaterialPass, MAX_MATERIALS),
    render_collections: [MAX_RENDER_LAYERS]RenderCollection = undefined,

    pub const PipelineHandle = struct { id: u32 };
    pub const MaterialHandle = struct { id: u32 };
    pub const MeshHandle = struct { id: u32 };
    pub const ObjectHandle = struct { id: u32 };
    pub const ImageHandle = struct { id: u32 };

    pub fn init(gpu: *const Gpu, window: *const Window, allocator: std.mem.Allocator) Renderer {
        const renderer = ffi.create_renderer(gpu.handle, window.handle).?;
        errdefer ffi.destroy_renderer(renderer);

        var result = Renderer{
            .handle = renderer,
            .meshes = FixedSlab(u32, MAX_MESHES).init(),
            .materials = FixedSlab(u32, MAX_MATERIALS).init(),
            .material_passes = FixedSlab(MaterialPass, MAX_MATERIALS).init(),
        };

        for (&result.render_collections) |*collection| {
            collection.* = RenderCollection.init(allocator);
        }

        return result;
    }

    pub fn deinit(self: *Renderer) void {
        ffi.destroy_renderer(self.handle);
    }

    pub fn createUiMaterial(self: *Renderer, image: ImageHandle, r: f32, g: f32, b: f32) !MaterialHandle {
        const id = ffi.create_ui_material(self.handle, image.id, r, g, b);
        const key, _ = try self.materials.append(id);
        return .{ .id = key };
    }

    pub fn createMeshMaterial(self: *Renderer, r: f32, g: f32, b: f32) !MaterialHandle {
        const id = ffi.create_mesh_material(self.handle, r, g, b);
        const key, _ = try self.materials.append(id);
        return .{ .id = key };
    }

    pub fn createMesh(self: *Renderer, vertices: []const u8, indices: []const u16) !MeshHandle {
        const id = ffi.create_mesh(self.handle, @constCast(@ptrCast(vertices.ptr)), vertices.len, @constCast(@ptrCast(indices.ptr)), indices.len);
        const key, _ = try self.meshes.append(id);
        return MeshHandle{ .id = key };
    }

    pub fn deleteMesh(self: *Renderer, mesh: MeshHandle) void {
        ffi.delete_mesh(self.handle, mesh.id);
    }

    pub fn addObject(self: *Renderer, mesh: MeshHandle, transform: Mat4, material: MaterialHandle, render_order: u8) !ObjectHandle {
        const material_passes = &self.render_collections[render_order].material_passes;
        if (material_passes.get(@intCast(material.id))) |mat_pass_id| {
            const material_pass = self.material_passes.get(mat_pass_id).?;
            try material_pass.mesh_passes.put(mesh.id);
        } else {
            var material_pass = MaterialPass{};
            material_pass.mesh_passes.put(mesh.id) catch unreachable;
            const mat_pass_id, _ = try self.material_passes.append(material_pass); // todo handle error
            try material_passes.put(@intCast(material.id), @intCast(mat_pass_id));
        }

        const render_mesh = self.meshes.get(mesh.id).?;
        const render_material = self.materials.get(material.id).?;

        const id = ffi.add_object(self.handle, render_mesh.*, transform.ptr(), render_material.*);
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

        for (&self.render_collections) |*collection| {
            var material_passes = collection.material_passes.iterator();
            while (material_passes.next()) |mat| {
                const material = self.materials.get(mat.key_ptr.*).?;
                ffi.set_material(self.handle, material.*);
                const material_pass = self.material_passes.get(mat.key_ptr.*).?;
                for (material_pass.mesh_passes.items()) |mesh_id| {
                    const mesh = self.meshes.get(mesh_id).?;
                    ffi.render_mesh(self.handle, material.*, mesh.*, ui_view_projection.ptr());
                }
            }
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
