const std = @import("std");
const Type = std.builtin.Type;

const engine = @import("engine");
const reflect = engine.utils.reflect;

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

pub var get_variant_from_type_constructor: gd.GDExtensionInterfaceGetVariantFromTypeConstructor = undefined;
pub var get_variant_to_type_constructor: gd.GDExtensionInterfaceGetVariantToTypeConstructor = undefined;
pub var variant_get_ptr_destructor: gd.GDExtensionInterfaceVariantGetPtrDestructor = undefined;
pub var classdb_construct_object2: gd.GDExtensionInterfaceClassdbConstructObject2 = undefined;
pub var classdb_register_extension_class2: gd.GDExtensionInterfaceClassdbRegisterExtensionClass2 = undefined;
pub var classdb_register_extension_class_method: gd.GDExtensionInterfaceClassdbRegisterExtensionClassMethod = undefined;
pub var object_set_instance: gd.GDExtensionInterfaceObjectSetInstance = undefined;
pub var object_set_instance_binding: gd.GDExtensionInterfaceObjectSetInstanceBinding = undefined;
pub var object_get_instance_binding: gd.GDExtensionInterfaceObjectGetInstanceBinding = undefined;
pub var mem_alloc: gd.GDExtensionInterfaceMemAlloc = undefined;
pub var mem_free: gd.GDExtensionInterfaceMemFree = undefined;
pub var string_new_with_utf8_chars: gd.GDExtensionInterfaceStringNewWithUtf8Chars = undefined;
pub var string_name_new_with_latin1_chars: gd.GDExtensionInterfaceStringNameNewWithLatin1Chars = undefined;
pub var int_constructor: gd.GDExtensionVariantFromTypeConstructorFunc = undefined;
pub var bool_constructor: gd.GDExtensionVariantFromTypeConstructorFunc = undefined;
pub var float_constructor: gd.GDExtensionVariantFromTypeConstructorFunc = undefined;
pub var object_constructor: gd.GDExtensionVariantFromTypeConstructorFunc = undefined;
pub var vector2_constructor: gd.GDExtensionVariantFromTypeConstructorFunc = undefined;
pub var string_destructor: gd.GDExtensionPtrDestructor = undefined;
pub var string_name_destructor: gd.GDExtensionPtrDestructor = undefined;
pub var variant_to_float: gd.GDExtensionTypeFromVariantConstructorFunc = undefined;
pub var variant_to_int: gd.GDExtensionTypeFromVariantConstructorFunc = undefined;
pub var variant_to_vector2: gd.GDExtensionTypeFromVariantConstructorFunc = undefined;

pub var class_lib: ?*anyopaque = undefined;

const gd_callbacks = gd.GDExtensionInstanceBindingCallbacks{
    .create_callback = null,
    .free_callback = null,
    .reference_callback = null,
};

pub fn initFunctions(get_proc_address: gd.GDExtensionInterfaceGetProcAddress, lib: gd.GDExtensionClassLibraryPtr) void {
    const getProcAddress = get_proc_address.?;
    get_variant_from_type_constructor = @ptrCast(getProcAddress("get_variant_from_type_constructor"));
    get_variant_to_type_constructor = @ptrCast(getProcAddress("get_variant_to_type_constructor"));
    variant_get_ptr_destructor = @ptrCast(getProcAddress("variant_get_ptr_destructor"));
    classdb_construct_object2 = @ptrCast(getProcAddress("classdb_construct_object2"));
    classdb_register_extension_class2 = @ptrCast(getProcAddress("classdb_register_extension_class2"));
    classdb_register_extension_class_method = @ptrCast(getProcAddress("classdb_register_extension_class_method"));
    object_set_instance = @ptrCast(getProcAddress("object_set_instance"));
    object_set_instance_binding = @ptrCast(getProcAddress("object_set_instance_binding"));
    object_get_instance_binding = @ptrCast(getProcAddress("object_get_instance_binding"));
    mem_alloc = @ptrCast(getProcAddress("mem_alloc"));
    mem_free = @ptrCast(getProcAddress("mem_free"));
    string_new_with_utf8_chars = @ptrCast(getProcAddress("string_new_with_utf8_chars"));
    string_name_new_with_latin1_chars = @ptrCast(getProcAddress("string_name_new_with_latin1_chars"));
    bool_constructor = get_variant_from_type_constructor.?(gd.GDEXTENSION_VARIANT_TYPE_BOOL);
    int_constructor = get_variant_from_type_constructor.?(gd.GDEXTENSION_VARIANT_TYPE_INT);
    float_constructor = get_variant_from_type_constructor.?(gd.GDEXTENSION_VARIANT_TYPE_FLOAT);
    object_constructor = get_variant_from_type_constructor.?(gd.GDEXTENSION_VARIANT_TYPE_OBJECT);
    vector2_constructor = get_variant_from_type_constructor.?(gd.GDEXTENSION_VARIANT_TYPE_VECTOR2);
    string_destructor = variant_get_ptr_destructor.?(gd.GDEXTENSION_VARIANT_TYPE_STRING);
    string_name_destructor = variant_get_ptr_destructor.?(gd.GDEXTENSION_VARIANT_TYPE_STRING_NAME);
    variant_to_float = get_variant_to_type_constructor.?(gd.GDEXTENSION_VARIANT_TYPE_FLOAT);
    variant_to_int = get_variant_to_type_constructor.?(gd.GDEXTENSION_VARIANT_TYPE_INT);
    variant_to_vector2 = get_variant_to_type_constructor.?(gd.GDEXTENSION_VARIANT_TYPE_VECTOR2);

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

fn typeToGd(ty: type) ?gd.GDExtensionVariantType {
    return switch (@typeInfo(ty)) {
        .void => null,

        .bool => gd.GDEXTENSION_VARIANT_TYPE_BOOL,

        .float => |float| if (float.bits == 64)
            gd.GDEXTENSION_VARIANT_TYPE_FLOAT
        else
            @compileError("only 64-bit float types are supported"),

        .int => gd.GDEXTENSION_VARIANT_TYPE_INT,

        .@"struct" => gd.GDEXTENSION_VARIANT_TYPE_OBJECT,

        .vector => |v| getGdVectorType(v),

        else => @compileError("type " ++ @typeName(ty) ++ " not supported"),
    };
}

fn getGdVectorType(v: std.builtin.Type.Vector) gd.GDExtensionVariantType {
    const isInt = switch (@typeInfo(v.child)) {
        .int => true,
        .float => |f| if (f.bits == 32) false else @compileError("only 32-bit float vectors are supported"),
        else => @compileError("vector type " ++ @typeName(v.child) ++ " not supported"),
    };

    return switch (v.len) {
        2 => if (isInt) gd.GDEXTENSION_VARIANT_TYPE_VECTOR2I else gd.GDEXTENSION_VARIANT_TYPE_VECTOR2,
        3 => if (isInt) gd.GDEXTENSION_VARIANT_TYPE_VECTOR3I else gd.GDEXTENSION_VARIANT_TYPE_VECTOR3,
        4 => if (isInt) gd.GDEXTENSION_VARIANT_TYPE_VECTOR4I else gd.GDEXTENSION_VARIANT_TYPE_VECTOR4,
        else => @compileError("vector type " ++ @typeName(v.child) ++ " not supported"),
    };
}

pub fn registerClass(
    Class: type,
    comptime parent: []const u8,
) void {
    const qualified_name = @typeName(Class);
    const dot_index = comptime std.mem.lastIndexOf(u8, qualified_name, ".") orelse 0;
    const struct_name = comptime qualified_name[dot_index + 1 ..];

    var class_name = createStringName(struct_name);
    defer string_name_destructor.?(&class_name);
    var parent_class_name = createStringName(parent);
    defer string_name_destructor.?(&parent_class_name);

    const Lifecycle = struct {
        fn create(data: ?*anyopaque) callconv(.C) gd.GDExtensionObjectPtr {
            _ = data;

            var parent_class = createStringName(parent);
            defer string_name_destructor.?(&parent_class);
            const object: gd.GDExtensionObjectPtr = classdb_construct_object2.?(&parent_class);

            var self: *Class = @alignCast(@ptrCast(mem_alloc.?(@sizeOf(Class)).?));
            self.object = object;

            var class = createStringName(struct_name);
            defer string_name_destructor.?(&class);
            object_set_instance.?(object, &class, self);
            object_set_instance_binding.?(object, class_lib, self, &gd_callbacks);

            return object;
        }

        fn free(data: ?*anyopaque, instance: gd.GDExtensionClassInstancePtr) callconv(.C) void {
            _ = data;

            if (instance == null) {
                return;
            }

            const gd_perception: *Class = @alignCast(@ptrCast(instance));
            mem_free.?(gd_perception);
        }
    };

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
        .create_instance_func = Lifecycle.create,
        .free_instance_func = Lifecycle.free,
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
            else => continue,
        };

        const return_ty = func_info.return_type.?;
        const return_type = comptime typeToGd(return_ty);

        const zig_param_count = func_info.params.len;
        var param_types: [zig_param_count - 1]gd.GDExtensionVariantType = undefined;

        inline for (1..zig_param_count) |i| {
            const param_type = func_info.params[i].type.?;
            param_types[i - 1] = typeToGd(param_type).?;
        }

        const ArgType = reflect.functionParamsIntoTuple(func_info.params);

        const Functions = struct {
            fn ptrcall(
                data: ?*anyopaque,
                instance: gd.GDExtensionClassInstancePtr,
                args: [*c]const gd.GDExtensionConstTypePtr,
                ret: gd.GDExtensionTypePtr,
            ) callconv(.C) void {
                _ = data;
                const self: *Class = @alignCast(@ptrCast(instance));

                var zig_args: ArgType = undefined;
                zig_args[0] = self;

                inline for (1..zig_param_count) |i| {
                    const arg_ptr = @as(*const func_info.params[i].type.?, @ptrCast(@alignCast(args[i - 1])));
                    zig_args[i] = arg_ptr.*;
                }

                if (return_type) |_| {
                    const result = @call(.auto, func, zig_args);
                    const ret_ptr: *return_ty = @alignCast(@ptrCast(ret));
                    ret_ptr.* = result;
                } else {
                    @call(.auto, func, zig_args);
                }
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

                if (argc < zig_param_count - 1) {
                    ret_error.*.@"error" = gd.GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
                    ret_error.*.expected = zig_param_count;
                    return;
                }

                if (argc > zig_param_count - 1) {
                    ret_error.*.@"error" = gd.GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
                    ret_error.*.expected = zig_param_count;
                    return;
                }

                const self: *Class = @alignCast(@ptrCast(instance));

                var zig_args: ArgType = undefined;
                zig_args[0] = self;

                inline for (1..zig_param_count) |i| {
                    const param_type = func_info.params[i].type.?;

                    const variant_to_type = switch (@typeInfo(param_type)) {
                        .float => variant_to_float.?,
                        .int => variant_to_int.?,
                        .vector => |v| switch (v.len) {
                            2 => variant_to_vector2.?,
                            else => @panic("Vector type not supported"),
                        },
                        else => @panic("Unsupported parameter type"),
                    };

                    var arg_value: param_type = undefined;
                    const arg_ptr: gd.GDExtensionVariantPtr = @constCast(argv[i - 1]);
                    variant_to_type(@ptrCast(&arg_value), arg_ptr);
                    zig_args[i] = arg_value;
                }

                if (return_type) |ty| {
                    const result = @call(.auto, func, zig_args);
                    switch (ty) {
                        gd.GDEXTENSION_VARIANT_TYPE_BOOL => bool_constructor.?(ret, @constCast(@ptrCast(&result))),
                        gd.GDEXTENSION_VARIANT_TYPE_FLOAT => float_constructor.?(ret, @constCast(@ptrCast(&result))),
                        gd.GDEXTENSION_VARIANT_TYPE_INT => int_constructor.?(ret, @constCast(@ptrCast(&result))),
                        gd.GDEXTENSION_VARIANT_TYPE_VECTOR2 => vector2_constructor.?(ret, @constCast(@ptrCast(&result))),
                        else => @panic("Unsupported return type in call()"),
                    }
                } else {
                    @call(.auto, func, zig_args);
                }
            }
        };

        registerMethod(
            struct_name,
            func_decl.name,
            return_type,
            Functions.call,
            Functions.ptrcall,
            &param_types,
        );
    }
}

pub fn registerMethod(
    class_name: []const u8,
    method_name: []const u8,
    return_ty: ?gd.GDExtensionVariantType,
    call: gd.GDExtensionClassMethodCall,
    ptrcall: gd.GDExtensionClassMethodPtrCall,
    argument_types: []const gd.GDExtensionVariantType,
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

    var arg_info_list: [16]gd.GDExtensionPropertyInfo = undefined;
    var arg_info_name_list: [16]StringName = undefined;
    var arg_info_hint_list: [16]String = undefined;
    var arg_info_class_list: [16]String = undefined;
    var arg_meta: [16]gd.GDExtensionClassMethodArgumentMetadata = undefined;

    for (argument_types, 0..) |arg_ty, i| {
        arg_info_name_list[i] = createStringName("");
        arg_info_hint_list[i] = createString("");
        arg_info_class_list[i] = createString("");

        arg_info_list[i] = gd.GDExtensionPropertyInfo{
            .name = &arg_info_name_list[i],
            .type = arg_ty,
            .hint = 0,
            .hint_string = &arg_info_hint_list[i],
            .class_name = &arg_info_class_list[i],
            .usage = PropertyUsageDefault,
        };

        arg_meta[i] = gd.GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    }

    defer {
        for (0..argument_types.len) |i| {
            string_name_destructor.?(&arg_info_name_list[i]);
            string_destructor.?(&arg_info_hint_list[i]);
            string_destructor.?(&arg_info_class_list[i]);
        }
    }

    const method_info = gd.GDExtensionClassMethodInfo{
        .name = &method_str,
        .method_userdata = null,
        .call_func = call,
        .ptrcall_func = ptrcall,
        .method_flags = gd.GDEXTENSION_METHOD_FLAGS_DEFAULT,
        .has_return_value = if (return_ty) |_| 1 else 0,
        .return_value_info = if (return_ty) |_| &return_info else null,
        .arguments_metadata = &arg_meta,
        .argument_count = @intCast(argument_types.len),
        .arguments_info = if (argument_types.len > 0) &arg_info_list else null,
    };

    classdb_register_extension_class_method.?(class_lib, &class_str, &method_info);
}
