const std = @import("std");
const builtin = @import("builtin");
const util = @import("util");

const ffi = @cImport({
    @cInclude("ffi.h");
});

const Gpu = @import("../gpu/gpu.zig").Gpu;
const Window = @import("../window/window.zig").Window;
const Mat4 = @import("engine").math.Mat4;
const FixedArrayList = @import("util").FixedArrayList;
const Slab = util.Slab;
const FixedSlab = util.FixedSlab;
const SparseIntSet = util.SparseIntSet;

const MAX_RENDER_LAYERS = 32;
const MAX_MATERIALS = 512;
const MAX_MESHES = 2048;
const MAX_MESH_PASSES = 256;
const MAX_OBJECT_PASSES = 1024;
const MAX_OBJECTS = 65536;

const Object = struct {
    transform: Mat4,
    mesh: u16,
    material: u16,
    render_order: u8,
};

const MeshPass = struct {
    objects: SparseIntSet(u16, MAX_OBJECT_PASSES) = .{},
};

const MaterialPass = struct {
    mesh_passes: std.AutoHashMap(u16, u16),

    pub fn init(allocator: std.mem.Allocator) MaterialPass {
        return MaterialPass{
            .mesh_passes = std.AutoHashMap(u16, u16).init(allocator),
        };
    }

    pub fn deinit(self: *MaterialPass) void {
        self.mesh_passes.deinit();
    }
};

const RenderCollection = struct {
    material_passes: std.AutoHashMap(u16, u16),

    pub fn init(allocator: std.mem.Allocator) RenderCollection {
        return RenderCollection{
            .material_passes = std.AutoHashMap(u16, u16).init(allocator),
        };
    }

    pub fn deinit(self: *RenderCollection) void {
        self.material_passes.deinit();
    }
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    handle: *ffi.Renderer,
    objects: Slab(Object),
    meshes: FixedSlab(ffi.Mesh, MAX_MESHES),
    mesh_passes: Slab(MeshPass),
    materials: FixedSlab(ffi.Material, MAX_MATERIALS),
    material_passes: FixedSlab(MaterialPass, MAX_MATERIALS),
    render_collections: [MAX_RENDER_LAYERS]RenderCollection = undefined,

    pub const PipelineHandle = struct { id: u32 };
    pub const MaterialHandle = struct { id: u32 };
    pub const MeshHandle = struct { id: u32 };
    pub const ObjectHandle = struct { id: u32 };
    pub const ImageHandle = struct { id: u32 };

    pub fn init(gpu: *const Gpu, window: *const Window, allocator: std.mem.Allocator) !Renderer {
        const renderer = ffi.create_renderer(gpu.handle, window.handle).?;
        errdefer ffi.destroy_renderer(renderer);

        var objects = try Slab(Object).init(allocator, 1024);
        errdefer objects.deinit();

        var mesh_passes = try Slab(MeshPass).init(allocator, 64);
        errdefer mesh_passes.deinit();

        var result = Renderer{
            .allocator = allocator,
            .handle = renderer,
            .objects = objects,
            .meshes = FixedSlab(ffi.Mesh, MAX_MESHES).init(),
            .mesh_passes = mesh_passes,
            .materials = FixedSlab(ffi.Material, MAX_MATERIALS).init(),
            .material_passes = FixedSlab(MaterialPass, MAX_MATERIALS).init(),
        };

        for (&result.render_collections) |*collection| {
            collection.* = RenderCollection.init(allocator);
        }

        return result;
    }

    pub fn deinit(self: *Renderer) void {
        ffi.destroy_renderer(self.handle);
        self.objects.deinit();
        self.mesh_passes.deinit();

        for (&self.render_collections) |*collection| {
            var material_passes = collection.material_passes.valueIterator();
            while (material_passes.next()) |mat_pass_id| {
                var material_pass = self.material_passes.get(mat_pass_id.*).?;
                material_pass.deinit();
            }

            collection.deinit();
        }
    }

    pub fn createUiMaterial(self: *Renderer, image: ImageHandle, r: f32, g: f32, b: f32) !MaterialHandle {
        const mat = ffi.create_ui_material(self.handle, image.id, r, g, b);
        const key, _ = try self.materials.append(mat);
        return .{ .id = key };
    }

    //pub fn createMeshMaterial(self: *Renderer, r: f32, g: f32, b: f32) !MaterialHandle {
    //    const id = ffi.create_mesh_material(self.handle, r, g, b);
    //    const key, _ = try self.materials.append(id);
    //    return .{ .id = key };
    //}

    pub fn createMesh(self: *Renderer, vertices: []const u8, indices: []const u16) !MeshHandle {
        const mesh = ffi.create_mesh(self.handle, @constCast(@ptrCast(vertices.ptr)), vertices.len, @constCast(@ptrCast(indices.ptr)), indices.len);
        const key, _ = try self.meshes.append(mesh);
        return MeshHandle{ .id = key };
    }

    pub fn deleteMesh(self: *Renderer, id: MeshHandle) void {
        const mesh = self.meshes.get(id.id).?;
        ffi.delete_mesh(self.handle, mesh);
    }

    pub fn addObject(self: *Renderer, mesh: MeshHandle, transform: Mat4, material: MaterialHandle, render_order: u8) !ObjectHandle {
        const material_pass = try self.getOrInsertMaterialPass(&self.render_collections[render_order], @intCast(material.id));
        const mesh_pass = try self.getOrInsertMeshPass(material_pass, @intCast(mesh.id));

        const obj_id, _ = try self.objects.insert(.{
            .transform = transform,
            .mesh = @intCast(mesh.id),
            .material = @intCast(material.id),
            .render_order = render_order,
        });
        try mesh_pass.objects.put(@intCast(obj_id));
        return ObjectHandle{ .id = @intCast(obj_id) };
    }

    pub fn setObjectMaterial(self: *Renderer, object: ObjectHandle, material: MaterialHandle) !void {
        const obj = self.objects.get(object.id).?;

        if (obj.material == material.id) return;

        const collection = &self.render_collections[obj.render_order];
        const material_pass_id = collection.material_passes.get(obj.material).?;
        const material_pass = self.material_passes.get(material_pass_id).?;
        const mesh_pass_id = material_pass.mesh_passes.get(obj.mesh).?;
        const mesh_pass = self.mesh_passes.get(mesh_pass_id).?;
        mesh_pass.objects.delete(@intCast(object.id)) catch unreachable;

        obj.material = @intCast(material.id);
        const new_mat_pass = try self.getOrInsertMaterialPass(collection, @intCast(material.id));
        const new_mesh_pass = try self.getOrInsertMeshPass(new_mat_pass, @intCast(obj.mesh));
        try new_mesh_pass.objects.put(@intCast(object.id));
    }

    pub fn setObjectTransform(self: *Renderer, object: ObjectHandle, transform: Mat4) void {
        self.objects.get(object.id).?.transform = transform;
    }

    pub fn deleteObject(self: *Renderer, object: ObjectHandle) void {
        const obj = self.objects.get(object.id).?;
        const collection = &self.render_collections[obj.render_order];
        const material_pass_id = collection.material_passes.get(obj.material).?;
        const material_pass = self.material_passes.get(material_pass_id).?;
        const mesh_pass_id = material_pass.mesh_passes.get(obj.mesh).?;
        const mesh_pass = self.mesh_passes.get(mesh_pass_id).?;
        mesh_pass.objects.delete(@intCast(object.id)) catch unreachable;
        self.objects.delete(object.id) catch unreachable;
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

    fn getOrInsertMaterialPass(self: *Renderer, collection: *RenderCollection, material_id: u16) !*MaterialPass {
        if (collection.material_passes.get(material_id)) |mat_pass_id| {
            return self.material_passes.get(mat_pass_id).?;
        } else {
            var new_pass = MaterialPass.init(self.allocator);
            errdefer new_pass.deinit();
            const mat_pass_id, const result = try self.material_passes.append(new_pass);
            errdefer self.material_passes.delete(mat_pass_id) catch unreachable;
            try collection.material_passes.put(material_id, @intCast(mat_pass_id));
            return result;
        }
    }

    fn getOrInsertMeshPass(self: *Renderer, pass: *MaterialPass, mesh_id: u16) !*MeshPass {
        if (pass.mesh_passes.get(mesh_id)) |mesh_pass_id| {
            return self.mesh_passes.get(mesh_pass_id).?;
        } else {
            const mesh_pass_id, const result = try self.mesh_passes.insert(.{});
            errdefer self.mesh_passes.delete(mesh_pass_id) catch unreachable;
            try pass.mesh_passes.put(mesh_id, @intCast(mesh_pass_id));
            return result;
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
                const mat_id = mat.key_ptr.*;
                const mat_pass_id = mat.value_ptr.*;

                const material = self.materials.get(mat_id).?;
                ffi.set_material(self.handle, material);

                const material_pass = self.material_passes.get(mat_pass_id).?;
                var mesh_passes = material_pass.mesh_passes.iterator();
                while (mesh_passes.next()) |mesh_entry| {
                    const mesh_id = mesh_entry.key_ptr.*;
                    const mesh_pass_id = mesh_entry.value_ptr.*;

                    const mesh = self.meshes.get(mesh_id).?;
                    ffi.set_mesh(self.handle, mesh);

                    const mesh_pass = self.mesh_passes.get(mesh_pass_id).?;
                    for (mesh_pass.objects.items()) |instance| {
                        const object = self.objects.get(instance).?;
                        const transform = ui_view_projection.matmul(&object.transform);
                        ffi.render_object(self.handle, transform.ptr());
                    }
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
