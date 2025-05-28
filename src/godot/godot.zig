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

const PropertyUsage = enum(u32) {
    none = 0,
    storage = 2,
    editor = 4,
    default = .storage | .editor,
};

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
    const string: *String = mem_alloc(@sizeOf(String));
    string_new_with_utf8_chars(string, utf8);
    return string;
}

pub fn createStringName(latin1: []const u8) StringName {
    var string_name: StringName = undefined;
    string_name_new_with_latin1_chars.?(&string_name, @ptrCast(latin1), 0);
    return string_name;
}

pub fn registerMethod(class_name: []const u8, method_name: []const u8, comptime function: anytype) void {
    var class_str = createStringName(class_name);
    defer string_name_destructor.?(&class_str);

    var method_str = createStringName(method_name);
    defer string_name_destructor.?(&method_str);

    const func_info = @typeInfo(@TypeOf(function));
    const params = func_info.@"fn".params;
    const return_ty = func_info.@"fn".return_type.?;
    const has_return = switch (@typeInfo(return_ty)) {
        std.builtin.Type.void => false,
        else => true,
    };

    var return_info: ?*gd.GDExtensionPropertyInfo = null;
    if (has_return) {
        return_info = gd.GDExtensionPropertyInfo{
            .name = createStringName(""),
            .type = switch (return_ty) {
                std.builtin.Type.Struct => gd.GDEXTENSION_VARIANT_TYPE_OBJECT,
                else => @compileError("return type " ++ @typeName(return_ty) ++ " not supported"),
            },
            .hint = 0,
            .hint_string = createString(""),
            .class_name = createString(""),
            .usage = PropertyUsage.default,
        };
    }

    defer if (has_return) {
        string_name_destructor.?(&return_info.name);
        string_destructor.?(&return_info.hint_string);
        string_destructor.?(&return_info.class_name);
    };

    const Functions = struct {
        fn ptrfunc(
            data: ?*anyopaque,
            instance: gd.GDExtensionClassInstancePtr,
            args: [*c]const gd.GDExtensionConstTypePtr,
            ret: gd.GDExtensionTypePtr,
        ) callconv(.C) void {
            _ = data;
            _ = instance;
            _ = args;
            _ = ret;
            function();
        }

        fn func(
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
            function();
        }
    };

    const method_info = gd.GDExtensionClassMethodInfo{
        .name = &method_str,
        .method_userdata = @constCast(@ptrCast(&function)),
        .call_func = Functions.func,
        .ptrcall_func = Functions.ptrfunc,
        .method_flags = gd.GDEXTENSION_METHOD_FLAGS_DEFAULT,
        .has_return_value = if (has_return) 1 else 0,
        .return_value_info = return_info,
        .arguments_metadata = gd.GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
        .argument_count = @intCast(params.len),
    };

    classdb_register_extension_class_method.?(class_lib, &class_str, &method_info);
}
