const std = @import("std");

const engine = @import("engine");

pub const gd = @cImport({
    @cInclude("godot/godot-cpp/gdextension/gdextension_interface.h");
});

comptime {
    _ = engine;
}

const String = usize;
const StringName = usize;

const PropertyUsageNone = 0;
const PropertyUsageStorage = 2;
const PropertyUsageEditor = 4;
const PropertyUsageDefault = PropertyUsageStorage | PropertyUsageEditor;

pub var variant_get_ptr_destructor: gd.GDExtensionInterfaceVariantGetPtrDestructor = undefined;
pub var classdb_construct_object: gd.GDExtensionInterfaceClassdbConstructObject = undefined;
pub var classdb_register_extension_class2: gd.GDExtensionInterfaceClassdbRegisterExtensionClass2 = undefined;
pub var classdb_register_extension_class_method: gd.GDExtensionInterfaceClassdbRegisterExtensionClassMethod = undefined;
pub var object_set_instance: gd.GDExtensionInterfaceObjectSetInstance = undefined;
pub var object_set_instance_binding: gd.GDExtensionInterfaceObjectSetInstanceBinding = undefined;
pub var mem_alloc: gd.GDExtensionInterfaceMemAlloc = undefined;
pub var mem_free: gd.GDExtensionInterfaceMemFree = undefined;
pub var string_new_with_utf8_chars: gd.GDExtensionInterfaceStringNewWithUtf8Chars = undefined;
pub var string_name_new_with_latin1_chars: gd.GDExtensionInterfaceStringNameNewWithLatin1Chars = undefined;
pub var string_destructor: gd.GDExtensionPtrDestructor = undefined;
pub var string_name_destructor: gd.GDExtensionPtrDestructor = undefined;

pub var class_lib: ?*anyopaque = undefined;

pub fn initFunctions(get_proc_address: gd.GDExtensionInterfaceGetProcAddress, lib: gd.GDExtensionClassLibraryPtr) void {
    const getProcAddress = get_proc_address.?;
    variant_get_ptr_destructor = @ptrCast(getProcAddress("variant_get_ptr_destructor"));
    classdb_construct_object = @ptrCast(getProcAddress("classdb_construct_object"));
    classdb_register_extension_class2 = @ptrCast(getProcAddress("classdb_register_extension_class2"));
    classdb_register_extension_class_method = @ptrCast(getProcAddress("classdb_register_extension_class_method"));
    object_set_instance = @ptrCast(getProcAddress("object_set_instance"));
    object_set_instance_binding = @ptrCast(getProcAddress("object_set_instance_binding"));
    mem_alloc = @ptrCast(getProcAddress("mem_alloc"));
    mem_free = @ptrCast(getProcAddress("mem_free"));
    string_new_with_utf8_chars = @ptrCast(getProcAddress("string_new_with_utf8_chars"));
    string_name_new_with_latin1_chars = @ptrCast(getProcAddress("string_name_new_with_latin1_chars"));
    string_destructor = variant_get_ptr_destructor.?(gd.GDEXTENSION_VARIANT_TYPE_STRING);
    string_name_destructor = variant_get_ptr_destructor.?(gd.GDEXTENSION_VARIANT_TYPE_STRING_NAME);

    class_lib = lib;
}

pub fn createString(utf8: []const u8) String {
    var string: String = undefined;
    string_new_with_utf8_chars.?(&string, @ptrCast(utf8));
    return string;
}

pub fn createStringName(latin1: []const u8) StringName {
    var string_name: StringName = undefined;
    string_name_new_with_latin1_chars.?(&string_name, @ptrCast(latin1), 0);
    return string_name;
}

pub fn registerClass(
    Class: type,
    parent: []const u8,
    on_create: gd.GDExtensionClassCreateInstance,
    on_destroy: gd.GDExtensionClassFreeInstance,
) void {
    const qualified_name = @typeName(Class);
    const dot_index = comptime std.mem.lastIndexOf(u8, qualified_name, ".") orelse 0;
    const struct_name = comptime qualified_name[dot_index + 1 ..];

    var class_name = createStringName(struct_name);
    defer string_name_destructor.?(&class_name);
    var parent_class_name = createStringName(parent);
    defer string_name_destructor.?(&parent_class_name);

    const class_info = gd.GDExtensionClassCreationInfo2{
        .is_virtual = 0,
        .is_abstract = 0,
        .is_exposed = 1,
        .set_func = null,
        .get_func = null,
        .get_property_list_func = null,
        .free_property_list_func = null,
        .property_can_revert_func = null,
        .property_get_revert_func = null,
        .validate_property_func = null,
        .notification_func = null,
        .to_string_func = null,
        .reference_func = null,
        .unreference_func = null,
        .create_instance_func = on_create,
        .free_instance_func = on_destroy,
        .recreate_instance_func = null,
        .get_virtual_func = null,
        .get_virtual_call_data_func = null,
        .call_virtual_with_data_func = null,
        .get_rid_func = null,
        .class_userdata = null,
    };
    classdb_register_extension_class2.?(class_lib, &class_name, &parent_class_name, &class_info);

    const func_decls = switch (@typeInfo(Class)) {
        .@"struct" => |structure| structure.decls,
        else => @compileError("can't register non-struct"),
    };

    inline for (func_decls) |func_decl| {
        const func = @field(Class, func_decl.name);
        const func_info = switch (@typeInfo(@TypeOf(func))) {
            std.builtin.Type.@"fn" => |f| f,
            else => @compileError("can't register non-struct"),
        };

        const return_ty = func_info.return_type.?;
        const return_type =
            switch (@typeInfo(return_ty)) {
                std.builtin.Type.void => null,
                std.builtin.Type.@"struct" => gd.GDEXTENSION_VARIANT_TYPE_OBJECT,
                else => @compileError("return type " ++ @typeName(return_ty) ++ " not supported"),
            };

        const Functions = struct {
            fn ptrcall(
                data: ?*anyopaque,
                instance: gd.GDExtensionClassInstancePtr,
                args: [*c]const gd.GDExtensionConstTypePtr,
                ret: gd.GDExtensionTypePtr,
            ) callconv(.C) void {
                _ = data;
                _ = instance;
                _ = args;
                _ = ret;
                func();
            }

            fn call(
                data: ?*anyopaque,
                instance: gd.GDExtensionClassInstancePtr,
                argv: [*c]const gd.GDExtensionConstVariantPtr,
                argc: gd.GDExtensionInt,
                ret: gd.GDExtensionVariantPtr,
                ret_error: [*c]gd.GDExtensionCallError,
            ) callconv(.C) void {
                _ = data;
                _ = instance;
                _ = argv;
                _ = argc;
                _ = ret;
                _ = ret_error;
                func();
            }
        };

        registerMethod(
            struct_name,
            func_decl.name,
            return_type,
            Functions.call,
            Functions.ptrcall,
        );
    }
}

pub fn registerMethod(
    class_name: []const u8,
    method_name: []const u8,
    return_ty: ?c_uint,
    call: gd.GDExtensionClassMethodCall,
    ptrcall: gd.GDExtensionClassMethodPtrCall,
) void {
    var class_str = createStringName(class_name);
    defer string_name_destructor.?(&class_str);

    var method_str = createStringName(method_name);
    defer string_name_destructor.?(&method_str);

    var name: StringName = undefined;
    var hint: String = undefined;
    var gd_class_name: String = undefined;
    var return_info: gd.GDExtensionPropertyInfo = undefined;
    if (return_ty) |ty| {
        name = createStringName("");
        hint = createString("");
        gd_class_name = createString("");
        return_info = gd.GDExtensionPropertyInfo{
            .name = &name,
            .type = ty,
            .hint = 0,
            .hint_string = &hint,
            .class_name = &gd_class_name,
            .usage = PropertyUsageDefault,
        };
    }

    defer if (return_ty) |_| {
        string_name_destructor.?(&name);
        string_destructor.?(&hint);
        string_destructor.?(&gd_class_name);
    };

    const method_info = gd.GDExtensionClassMethodInfo{
        .name = &method_str,
        .method_userdata = null,
        .call_func = call,
        .ptrcall_func = ptrcall,
        .method_flags = gd.GDEXTENSION_METHOD_FLAGS_DEFAULT,
        .has_return_value = if (return_ty) |_| 1 else 0,
        .return_value_info = if (return_ty) |_| &return_info else null,
        .arguments_metadata = gd.GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
        .argument_count = 0,
    };

    classdb_register_extension_class_method.?(class_lib, &class_str, &method_info);
}
